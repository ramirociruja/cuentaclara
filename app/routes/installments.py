# routes/installments.py
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Optional, List

from fastapi import APIRouter, HTTPException, Depends, status, Query
from sqlalchemy import func, Float, or_, case, and_, not_, func
from sqlalchemy.orm import Session  

from app.database.db import get_db
from app.models.models import Customer, Installment, Loan, Payment, PaymentAllocation, Purchase, Employee
from app.schemas.installments import (
    InstallmentDetailedOut, InstallmentListOut, InstallmentOut,
    InstallmentPaymentRequest, InstallmentSummaryOut, InstallmentUpdate, OverdueInstallmentOut,
    InstallmentPaymentResult
)
from app.utils.auth import get_current_user
from app.utils.ledger import recompute_ledger_for_loan
from app.utils.license import ensure_company_active
from app.utils.status import update_status_if_fully_paid

# 👇 NUEVO: estados canónicos y normalizador
from app.constants import InstallmentStatus
from app.utils.normalize import norm_installment_status
from app.utils.time_windows import parse_iso_aware_utc, local_dates_to_utc_window, AR_TZ
from zoneinfo import ZoneInfo


router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],  # 👈 exige Bearer en todas las rutas
)

EPS = Decimal("0.000001")  # tolerancia para redondeos


# =========================
#        HELPERS
# =========================
def _404():
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recurso no encontrado")

BLOCKED_STATUSES = ['canceled', 'cancelled', 'refinanced', 'cancelado', 'refinanciado']

def loan_is_effective_clause(Installment, Loan):
    """Devuelve una cláusula que deja pasar:
       - Cuotas sin préstamo (compras), o
       - Cuotas de préstamos cuyo estado NO es cancelado/refinanciado (ni flags).
    """
    return or_(
        Installment.loan_id.is_(None),
        and_(
            # status string no bloqueado o nulo
            or_(Loan.status.is_(None), not_(Loan.status.in_(BLOCKED_STATUSES))),
            # flags booleanos coherentes
            or_(getattr(Loan, 'is_canceled', None).is_(None), Loan.is_canceled.is_(False))
            if hasattr(Loan, 'is_canceled') else True,
            or_(getattr(Loan, 'is_refinanced', None).is_(None), Loan.is_refinanced.is_(False))
            if hasattr(Loan, 'is_refinanced') else True,
        ),
    )


def _get_installment_scoped(installment_id: int, db: Session, current: Employee) -> Installment:
    """Devuelve la cuota si pertenece a la empresa del token; si no, 404."""
    row = (
        db.query(Installment, Customer)
          .outerjoin(Loan, Installment.loan_id == Loan.id)
          .outerjoin(Purchase, Installment.purchase_id == Purchase.id)
          .outerjoin(Customer, or_(Customer.id == Loan.customer_id, Customer.id == Purchase.customer_id))
          .filter(Installment.id == installment_id, Customer.company_id == current.company_id)
          .first()
    )
    if not row:
        _404()
    inst, _ = row
    return inst

def _assert_customer_scoped(customer_id: int, db: Session, current: Employee) -> Customer:
    cust = db.query(Customer).filter(Customer.id == customer_id).first()
    if not cust or cust.company_id != current.company_id:
        _404()
    return cust

def _assert_loan_scoped(loan_id: int, db: Session, current: Employee) -> Loan:
    loan = (
        db.query(Loan)
          .join(Customer, Customer.id == Loan.customer_id)
          .filter(Loan.id == loan_id, Customer.company_id == current.company_id)
          .first()
    )
    if not loan:
        _404()
    return loan


# =========================
#        PAY
# =========================

@router.post("/{installment_id}/pay", response_model=InstallmentPaymentResult)
def pay_installment(
    installment_id: int,
    payment_data: InstallmentPaymentRequest,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Registra un pago para una cuota específica.
    Ahora NO muta manualmente paid_amount/status ni loan.total_due.
    Crea el Payment y luego ejecuta recompute_ledger_for_loan para:
      - recalcular todas las cuotas del préstamo afectado
      - poblar payment_allocations consistentes
    """
    installment = _get_installment_scoped(installment_id, db, current)

    # --- Validaciones de monto ---
    def D(x): return Decimal(str(x))
    amount_to_pay = D(payment_data.amount)
    if amount_to_pay <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El monto debe ser mayor a cero"
        )

    installment_amount = D(installment.amount)
    paid_amount = D(installment.paid_amount or 0)

    # Bloquear doble pago si ya está completamente pagada
    if (paid_amount + EPS) >= installment_amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta cuota ya está pagada completamente"
        )

    remaining_amount = (installment_amount - paid_amount).quantize(Decimal("0.000001"))
    if amount_to_pay - remaining_amount > EPS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El monto excede el saldo pendiente. Máximo a pagar: {remaining_amount}"
        )

    # --- Crear Payment (NO tocar paid_amount/status acá) ---
    try:
        # normalizamos la fecha a UTC aware
        if payment_data.payment_date:
            # si es datetime con tz → lo pasamos a UTC; si es naive → asumimos UTC
            pdt = payment_data.payment_date
            if pdt.tzinfo is None:
                pdt = pdt.replace(tzinfo=timezone.utc)
            payment_dt_utc = pdt.astimezone(timezone.utc)
        else:
            payment_dt_utc = datetime.now(timezone.utc)

        payment_row = Payment(
            amount=float(payment_data.amount),
            loan_id=installment.loan_id if installment.loan_id else None,
            purchase_id=installment.purchase_id if installment.purchase_id else None,
            payment_date=payment_dt_utc,
            payment_type=payment_data.payment_type,
            description=payment_data.description,
            collector_id=current.id,
        )
        db.add(payment_row)
        db.commit()
        db.refresh(payment_row)
        if installment.loan_id:
            recompute_ledger_for_loan(db, installment.loan_id)
            db.commit()
            update_status_if_fully_paid(db, loan_id=installment.loan_id, purchase_id=None)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error al registrar Payment: {e}")

    # --- Recompute (reconstruye cuotas + allocations para préstamos) ---
    parent_loan_id = installment.loan_id
    parent_purchase_id = installment.purchase_id

    if parent_loan_id:
        recompute_ledger_for_loan(db, parent_loan_id)
        db.commit()

    # Estado agregado del padre (si usás esta utilidad para loan/purchase)
    update_status_if_fully_paid(db, loan_id=parent_loan_id, purchase_id=parent_purchase_id)

    # Refrescar cuota para devolverla consistente post-recompute
    db.refresh(installment)

    return {
        "payment_id": payment_row.id,
        "installment": installment
    }



# =========================
#        LIST
# =========================
@router.get("/", response_model=List[InstallmentListOut])
def get_all_installment(
    employee_id: Optional[int] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    only_pending: Optional[bool] = None,
    status: Optional[str] = None,
    province: Optional[str] = Query(None),   # 👈 NUEVO (opcional)
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    q = (
        db.query(
            Installment,
            case(
                (Installment.loan_id.is_not(None), "loan"),
                else_="purchase",
            ).label("debt_type"),
            func.btrim(func.concat_ws(' ', Customer.first_name, Customer.last_name)).label("customer_name"),
            Customer.id.label("customer_id"),
            Customer.phone.label("customer_phone"),
            Loan.collection_day.label("collection_day"),
            Customer.province.label("customer_province"),        # 👈 NUEVO en SELECT
        )
        .outerjoin(Loan, Installment.loan_id == Loan.id)
        .outerjoin(Purchase, Installment.purchase_id == Purchase.id)
        .outerjoin(
            Customer,
            or_(Customer.id == Loan.customer_id, Customer.id == Purchase.customer_id)
        )
        .filter(Customer.company_id == current.company_id)
        .filter(loan_is_effective_clause(Installment, Loan))
    )

    if employee_id is not None:
        q = q.filter(
            or_(
                # Cuotas de PRÉSTAMOS: usar el dueño del préstamo
                and_(
                    Installment.loan_id.is_not(None),
                    Loan.employee_id == employee_id,
                ),
                # Cuotas de COMPRAS: seguimos usando el owner del cliente
                and_(
                    Installment.loan_id.is_(None),
                    Customer.employee_id == employee_id,
                ),
            )
        )

    # 👇 filtro por provincia (sólo si viene)
    if province:
        q = q.filter(Customer.province == province)

    # Rango local → ventana UTC
    if date_from is not None and date_to is not None:
        start_utc, end_utc_excl = local_dates_to_utc_window(date_from, date_to, zone)
        q = q.filter(Installment.due_date >= start_utc)
        q = q.filter(Installment.due_date <  end_utc_excl)

    if only_pending is True:
        q = q.filter(Installment.is_paid.is_(False))

    if status is not None:
        normalized = norm_installment_status(status).value
        q = q.filter(Installment.status == normalized)

    rows = q.order_by(Installment.due_date.asc(), Installment.id.asc()).all()

    out: list[InstallmentListOut] = []
    today_local = datetime.now(zone).date()

    for (
        inst,
        debt_type,
        customer_name,
        customer_id,
        customer_phone,
        collection_day,
        customer_province,          # 👈 NUEVO en unpack
    ) in rows:
        amount = float(inst.amount or 0.0)

        due_dt = getattr(inst, "due_date", None)
        if isinstance(due_dt, datetime):
            due_only = due_dt.astimezone(zone).date()
        else:
            due_only = due_dt or today_local

        is_paid = bool(getattr(inst, "is_paid", getattr(inst, "paid", False)))
        status_val = inst.status or (InstallmentStatus.PAID.value if is_paid else InstallmentStatus.PENDING.value)

        number = int(getattr(inst, "number", 0) or 0)
        paid_amount = float(getattr(inst, "paid_amount", 0.0) or 0.0)

        iso_db = getattr(inst, "is_overdue", None)
        if iso_db is None:
            is_overdue = (not is_paid) and (due_only < today_local)
        else:
            is_overdue = bool(iso_db)

        out.append(
            InstallmentListOut(
                id=inst.id,
                amount=amount,
                due_date=due_only,
                status=status_val,
                is_paid=is_paid,
                loan_id=inst.loan_id,
                is_overdue=is_overdue,
                number=number,
                paid_amount=paid_amount,
                customer_name=customer_name,
                debt_type=debt_type,
                customer_id=customer_id,
                customer_phone=customer_phone,
                collection_day=collection_day,
                customer_province=customer_province,  # 👈 NUEVO en salida
            )
        )
    return out





# =========================
#   BY CUSTOMER (scoped)
# =========================

@router.get("/overdue/by-customer/{customer_id}", response_model=List[InstallmentOut])
def get_overdue_installment_by_customer_1(
    customer_id: int,
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _ = _assert_customer_scoped(customer_id, db, current)
    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()

    q = (
        db.query(Installment)
        .filter(
            Installment.status != InstallmentStatus.PAID.value,
            or_(
                Installment.loan.has(Loan.customer_id == customer_id),
                Installment.purchase.has(Purchase.customer_id == customer_id),
            )
        )
    )
    rows = q.all()

    out = []
    for inst in rows:
        dd = inst.due_date
        if isinstance(dd, datetime):
            due_local = dd.astimezone(zone).date()
        else:
            due_local = dd
        if due_local and due_local < today_local:
            out.append(inst)
    return out


@router.get("/by-customer/{customer_id}/overdue", response_model=List[InstallmentOut])
def get_overdue_installment_by_customer_2(
    customer_id: int,
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _ = _assert_customer_scoped(customer_id, db, current)
    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()

    q = (
        db.query(Installment)
        .join(Loan, isouter=True)
        .join(Purchase, isouter=True)
        .filter(
            or_(Loan.customer_id == customer_id, Purchase.customer_id == customer_id),
            Installment.status == InstallmentStatus.OVERDUE.value,
        )
    )
    rows = q.all()

    out = []
    for inst in rows:
        dd = inst.due_date
        due_local = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd
        if due_local and due_local < today_local:
            out.append(inst)
    return out


@router.get("/next/by-customer/{customer_id}", response_model=Optional[InstallmentOut])
def get_next_installment_by_customer(
    customer_id: int,
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _ = _assert_customer_scoped(customer_id, db, current)
    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone)

    # buscar la primera con due_date >= hoy local
    rows = (
        db.query(Installment)
        .join(Loan, isouter=True).join(Purchase, isouter=True)
        .filter(
            or_(Loan.customer_id == customer_id, Purchase.customer_id == customer_id),
            Installment.status != InstallmentStatus.PAID.value,
        )
        .order_by(Installment.due_date.asc())
        .all()
    )

    for inst in rows:
        dd = inst.due_date
        dd_local = dd.astimezone(zone) if isinstance(dd, datetime) else datetime.combine(dd, datetime.min.time(), tzinfo=zone)
        if dd_local >= today_local:
            return inst
    return None



@router.get("/summary/{customer_id}")
def get_debt_summary(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    customer = _assert_customer_scoped(customer_id, db, current)
    today = datetime.utcnow()

    all_installment = db.query(Installment).filter(
        or_(
            Installment.loan_id.in_([loan.id for loan in customer.loan]),
            Installment.purchase_id.in_([purchase.id for purchase in customer.purchases])
        )
    ).all()

    # tolera 'paid' o 'is_paid'
    def is_paid(inst: Installment) -> bool:
        return bool(getattr(inst, "is_paid", getattr(inst, "paid", False)))

    total_due = sum(inst.amount for inst in all_installment if not is_paid(inst))
    overdue = sum(inst.amount for inst in all_installment if not is_paid(inst) and inst.due_date < today)
    upcoming = sum(inst.amount for inst in all_installment if not is_paid(inst) and inst.due_date >= today)

    return {
        "total_due": float(total_due or 0.0),
        "overdue": float(overdue or 0.0),
        "upcoming": float(upcoming or 0.0)
    }


@router.get("/by-customer/{customer_id}/overdue-count", response_model=int)
def get_overdue_installment_count_by_customer(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    customer = _assert_customer_scoped(customer_id, db, current)
    today = datetime.utcnow()

    overdue_installment_count = db.query(Installment).join(Loan, isouter=True).join(Purchase, isouter=True).filter(
        or_(
            Loan.customer_id == customer.id,
            Purchase.customer_id == customer.id
        ),
        Installment.due_date < today,
        Installment.is_paid == False  # noqa: E712
    ).count()
    return int(overdue_installment_count or 0)


@router.get("/summary", response_model=InstallmentSummaryOut)
def installments_summary(
    employee_id: Optional[int] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    province: Optional[str] = Query(None),   # 👈 NUEVO (opcional)
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    base = (
        db.query(Installment)
          .outerjoin(Loan, Installment.loan_id == Loan.id)
          .outerjoin(Purchase, Installment.purchase_id == Purchase.id)
          .outerjoin(
              Customer,
              or_(Customer.id == Loan.customer_id, Customer.id == Purchase.customer_id)
          )
          .filter(Customer.company_id == current.company_id)
          .filter(loan_is_effective_clause(Installment, Loan))  # excluir loans bloqueados
    )

    if employee_id is not None:
        base = base.filter(
            or_(
                # Cuotas de PRÉSTAMOS: usar el dueño del préstamo
                and_(
                    Installment.loan_id.is_not(None),
                    Loan.employee_id == employee_id,
                ),
                # Cuotas de COMPRAS: seguimos usando el owner del cliente
                and_(
                    Installment.loan_id.is_(None),
                    Customer.employee_id == employee_id,
                ),
            )
        )

    # 👇 filtro por provincia (sólo si viene)
    if province:
        base = base.filter(Customer.province == province)

    # Rango local → ventana UTC
    if date_from is not None and date_to is not None:
        start_utc, end_utc_excl = local_dates_to_utc_window(date_from, date_to, zone)
        base = base.filter(Installment.due_date >= start_utc)
        base = base.filter(Installment.due_date <  end_utc_excl)

    pending_count = base.filter(Installment.is_paid.is_(False)).count()
    paid_count    = base.filter(Installment.is_paid.is_(True)).count()

    # overdue por día LOCAL
    rows_due = base.with_entities(Installment.id, Installment.due_date, Installment.is_paid).all()
    today_local = datetime.now(zone).date()
    overdue_count = 0
    for _id, dd, is_paid in rows_due:
        if bool(is_paid):
            continue
        due_local = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd
        if due_local and due_local < today_local:
            overdue_count += 1

    total_amount = float(
        base.with_entities(func.coalesce(func.sum(Installment.amount), 0.0)).scalar() or 0.0
    )
    pending_amount = float(
        base.filter(Installment.is_paid.is_(False))
            .with_entities(func.coalesce(func.sum(Installment.amount), 0.0))
            .scalar() or 0.0
    )

    return InstallmentSummaryOut(
        pending_count=int(pending_count or 0),
        paid_count=int(paid_count or 0),
        overdue_count=int(overdue_count or 0),
        total_amount=total_amount,
        pending_amount=pending_amount,
    )



from app.schemas.installments import InstallmentOut, InstallmentUpdate

@router.put("/{installment_id}", response_model=InstallmentOut)
def update_installment(
    installment_id: int,
    body: InstallmentUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ins = db.query(Installment).get(installment_id)
    if not ins:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")

    # Validar alcance por empresa (vía loan/purchase -> company)
    parent_company_id = None
    if ins.loan_id:
        loan = db.query(Loan).get(ins.loan_id)
        if not loan:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")
        parent_company_id = loan.company_id
    elif ins.purchase_id:
        purchase = db.query(Purchase).get(ins.purchase_id)
        if not purchase:
            raise HTTPException(status_code=404, detail="Compra no encontrada")
        parent_company_id = purchase.company_id

    if parent_company_id is not None and parent_company_id != current.company_id:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")

    if body.amount is not None:
        if body.amount <= 0:
            raise HTTPException(status_code=400, detail="Monto inválido")
        if ins.paid_amount and body.amount < ins.paid_amount:
            raise HTTPException(status_code=400, detail="No puede ser menor a lo ya pagado")
        ins.amount = body.amount
        # Recalcular estado simple con canónicos EN
        if (ins.paid_amount or 0) >= ins.amount:
            ins.is_paid = True
            ins.status = InstallmentStatus.PAID.value
        elif (ins.paid_amount or 0) > 0:
            ins.is_paid = False
            ins.status = InstallmentStatus.PARTIAL.value
        else:
            ins.is_paid = False
            ins.status = InstallmentStatus.PENDING.value

    if body.due_date is not None:
        # body.due_date puede venir como date; normalizamos a datetime (00:00)
        # ANTES: naive local → ahora hacemos local midnight → UTC
        zone = AR_TZ  # o parametrizá por compañía/usuario
        local_midnight = datetime.combine(body.due_date, datetime.min.time()).replace(tzinfo=zone)
        ins.due_date = local_midnight.astimezone(timezone.utc)

    # Si viene status en el body, normalizamos (ES/EN) y seteamos canónico
    if hasattr(body, "status") and body.status is not None:
        ins.status = norm_installment_status(body.status).value
        # Ajuste de is_paid derivado (por consistencia)
        ins.is_paid = (ins.status == InstallmentStatus.PAID.value)

    db.add(ins)
    db.commit()
    db.refresh(ins)

    # Actualizar estado y saldo del padre
    from app.utils.status import update_status_if_fully_paid
    update_status_if_fully_paid(db, loan_id=ins.loan_id, purchase_id=ins.purchase_id)

    return InstallmentOut.from_orm(ins)


@router.get("/{installment_id}/payments")
def payments_for_installment(
    installment_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ins = db.query(Installment).get(installment_id)
    if not ins:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")

    q = (
        db.query(Payment)
        .join(PaymentAllocation, PaymentAllocation.payment_id == Payment.id)
        .filter(PaymentAllocation.installment_id == installment_id, Payment.is_voided.is_(False))
        .order_by(Payment.payment_date.desc(), Payment.id.desc())
    )
    rows = q.all()

    return [
        {
            "id": p.id,
            "loan_id": p.loan_id,
            "amount": p.amount,
            "payment_date": p.payment_date.isoformat() if p.payment_date else None,
            "payment_type": p.payment_type,
            "description": p.description,
        }
        for p in rows
    ]
