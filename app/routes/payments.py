from typing import Optional
from zoneinfo import ZoneInfo
from fastapi import APIRouter, Body, HTTPException, Depends, Query, Path
from pydantic import BaseModel
from sqlalchemy.orm import Session, aliased, joinedload
from datetime import datetime, timezone, date, time, timedelta
from sqlalchemy import func, or_
from sqlalchemy.exc import SQLAlchemyError

from app.database.db import get_db
from app.models.models import (
    Employee,
    Payment,
    Loan,
    Purchase,
    Customer,
    Installment,
    PaymentAllocation,
)
from app.schemas.payments import (
    PaymentCreate,
    PaymentOut,
    PaymentDetailOut,
    PaymentsSummaryResponse,
    PaymentUpdate,
)
from app.utils.license import ensure_company_active
from app.utils.status import update_status_if_fully_paid
from app.utils.auth import get_current_user
from app.utils.ledger import recompute_ledger_for_loan
from app.utils.time_windows import local_dates_to_utc_window as _local_dates_to_utc_window

# Helpers de allocations
from app.utils.allocations import (
    # allocate_payment_for_loan,  # (Se usará cuando registremos allocations en el flujo de imputación)
    delete_allocations_for_payment,
)
from app.utils.time_windows import parse_iso_aware_utc, local_dates_to_utc_window, AR_TZ

router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)]  # 🔒 exige Bearer válido en todo el router
)

@router.get("/summary", response_model=PaymentsSummaryResponse)
def get_payments_summary(
    # admitimos ambos nombres para compat
    date_from: Optional[str] = Query(None, alias="date_from"),
    date_to:   Optional[str] = Query(None, alias="date_to"),
    start_date: Optional[str] = Query(None, alias="start_date"),
    end_date:   Optional[str] = Query(None, alias="end_date"),
    employee_id: Optional[int] = Query(None),  # <- ahora será el collector_id
    province: Optional[str] = Query(None),
    tz: Optional[str] = Query(None),   # zona horaria del usuario (default AR)
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    raw_from = date_from or start_date
    raw_to   = date_to   or end_date
    zone = ZoneInfo(tz) if tz else AR_TZ

    start_utc: Optional[datetime] = None
    end_utc_excl: Optional[datetime] = None

    def _looks_like_date(s: Optional[str]) -> bool:
        if not s:
            return False
        return len(s) == 10 and s[4] == '-' and s[7] == '-'

    if raw_from and raw_to and _looks_like_date(raw_from) and _looks_like_date(raw_to):
        dfrom = date.fromisoformat(raw_from)
        dto   = date.fromisoformat(raw_to)
        start_utc, end_utc_excl = _local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(raw_from)
        end_utc   = parse_iso_aware_utc(raw_to)
        end_utc_excl = end_utc

    L  = aliased(Loan)
    P  = aliased(Purchase)
    CL = aliased(Customer)
    CP = aliased(Customer)

    base = (
        db.query(Payment)
          .outerjoin(L, Payment.loan_id == L.id)
          .outerjoin(CL, L.customer_id == CL.id)
          .outerjoin(P, Payment.purchase_id == P.id)
          .outerjoin(CP, P.customer_id == CP.id)
          .filter(Payment.is_voided == False)
          .filter(or_(CL.company_id == current.company_id,
                      CP.company_id == current.company_id))
    )

    if start_utc is not None:
        base = base.filter(Payment.payment_date >= start_utc)
    if end_utc_excl is not None:
        base = base.filter(Payment.payment_date < end_utc_excl)

    # 🔴 CAMBIO CLAVE: ahora filtra por collector_id
    if employee_id is not None:
        base = base.filter(Payment.collector_id == employee_id)

    if province:
        base = base.filter(or_(CL.province == province,
                               CP.province == province))

    total_q = base.with_entities(func.coalesce(func.sum(Payment.amount), 0.0))
    total = float(total_q.scalar() or 0.0)

    tzname = (tz or "America/Argentina/Buenos_Aires")
    day_local = func.date(func.timezone(tzname, Payment.payment_date))
    by_day_rows = (
        base.with_entities(
            day_local.label("day"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("amount"),
        )
        .group_by(day_local)
        .order_by(day_local)
        .all()
    )
    by_day = [{"date": r.day, "amount": float(r.amount)} for r in by_day_rows]

    return PaymentsSummaryResponse(total_amount=total, by_day=by_day)



# Register a new payment
@router.post("/", response_model=PaymentOut)
def create_payment(
    payment: PaymentCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    if not payment.loan_id and not payment.purchase_id:
        raise HTTPException(status_code=400, detail="Debe indicar loan_id o purchase_id")

    # ⏰ Siempre UTC aware
    now_utc = datetime.now(timezone.utc)

    # --- Validar scoping por empresa ---
    if payment.loan_id:
        # Si usás SQLAlchemy 1.4+: loan = db.get(Loan, payment.loan_id)
        loan = db.query(Loan).get(payment.loan_id)
        if not loan:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")
        if loan.company_id != current.company_id:
            raise HTTPException(status_code=403, detail="No autorizado para este préstamo")

    if payment.purchase_id:
        purchase = db.query(Purchase).get(payment.purchase_id)
        if not purchase:
            raise HTTPException(status_code=404, detail="Compra no encontrada")
        if purchase.company_id != current.company_id:
            raise HTTPException(status_code=403, detail="No autorizado para esta compra")

    # --- Crear pago en UTC ---
    new_p = Payment(
        amount=payment.amount,
        payment_date=now_utc,            # 👈 guardado canonical en UTC (timestamptz)
        loan_id=payment.loan_id,
        purchase_id=payment.purchase_id,
        payment_type=payment.payment_type,
        description=payment.description,
        collector_id=current.id,
    )

    db.add(new_p)
    db.commit()
    db.refresh(new_p)

    # --- Actualizaciones derivadas (no bloquear alta ante errores) ---
    try:
        if new_p.loan_id:
            update_status_if_fully_paid(db, loan_id=new_p.loan_id, purchase_id=None)
            recompute_ledger_for_loan(db, new_p.loan_id)
            db.commit()
        if new_p.purchase_id:
            update_status_if_fully_paid(db, loan_id=None, purchase_id=new_p.purchase_id)
            db.commit()
    except Exception:
        # no romper alta si algo falla en utilidades
        pass

    # NOTA:
    # Las imputaciones (PaymentAllocation) las hacés en el flujo específico de imputación,
    # por eso no se tocan aquí.

    return new_p


def mark_next_installment_pending(db: Session, loan_id: int = None, purchase_id: int = None):
    query = db.query(Installment).filter(
        Installment.status != "paid"
    )

    if loan_id:
        query = query.filter(Installment.loan_id == loan_id)
    elif purchase_id:
        query = query.filter(Installment.purchase_id == purchase_id)

    next_installment = query.order_by(Installment.due_date).first()

    if next_installment and next_installment.status != "pending":
        next_installment.status = "pending"
        db.commit()


# Get all payments
@router.get("/", response_model=list[PaymentOut])
def list_payments(
    start_date: str | None = Query(None),
    end_date: str | None = Query(None),
    employee_id: int | None = Query(None),
    province: str | None = Query(None),   # 👈 opcional
    tz: str | None = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: str | None) -> bool:
        return bool(s) and len(s) == 10 and s[4] == '-' and s[7] == '-'

    start_utc = None
    end_utc_excl = None

    if _looks_like_date(start_date) and _looks_like_date(end_date):
        dfrom = date.fromisoformat(start_date) if start_date else None
        dto   = date.fromisoformat(end_date)   if end_date   else None
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(start_date)
        end_utc   = parse_iso_aware_utc(end_date)
        end_utc_excl = end_utc

    L  = aliased(Loan)
    P  = aliased(Purchase)
    CL = aliased(Customer)
    CP = aliased(Customer)

    q = (
        db.query(Payment)
          .outerjoin(L, Payment.loan_id == L.id)
          .outerjoin(CL, L.customer_id == CL.id)
          .outerjoin(P, Payment.purchase_id == P.id)
          .outerjoin(CP, P.customer_id == CP.id)
          .options(
              joinedload(Payment.loan).joinedload(Loan.customer),
              joinedload(Payment.purchase).joinedload(Purchase.customer),
          )
          .filter(Payment.is_voided == False)
          .filter(
              or_(
                  CL.company_id == current.company_id,
                  CP.company_id == current.company_id,
              )
          )
    )

    if start_utc is not None:
        q = q.filter(Payment.payment_date >= start_utc)
    if end_utc_excl is not None:
        q = q.filter(Payment.payment_date < end_utc_excl)

    # 🔴 AQUÍ el cambio: usar collector_id
    if employee_id is not None:
        q = q.filter(Payment.collector_id == employee_id)

    if province:
        q = q.filter(or_(CL.province == province, CP.province == province))

    rows = q.order_by(Payment.payment_date.desc(), Payment.id.desc()).all()

    out: list[PaymentOut] = []
    for p in rows:
        loan = p.loan
        purch = p.purchase
        cust = (loan.customer if loan else None) or (purch.customer if purch else None)

        out.append(PaymentOut(
            id=p.id,
            amount=float(p.amount or 0),
            payment_date=p.payment_date,
            loan_id=p.loan_id,
            purchase_id=p.purchase_id,
            payment_type=p.payment_type,
            description=p.description,
            customer_id=cust.id if cust else None,
            customer_name=(f"{(cust.last_name or '').strip()} {(cust.first_name or '').strip()}".strip() if cust else None),
            customer_province=(cust.province if cust else None),
            collector_id=p.collector_id,
            collector_name=p.collector.name if p.collector else None,
        ))

    return out


def _ensure_scope_and_get_context(db: Session, payment: Payment, current: Employee):
    """
    Valida que el Payment pertenezca a la misma empresa que el usuario
    y arma contexto de cliente/empresa para el recibo.
    """
    def _full_name(cust: Customer | None) -> str | None:
        if not cust:
            return None
        fn = (getattr(cust, "first_name", "") or "").strip()
        ln = (getattr(cust, "last_name", "") or "").strip()
        full = f"{fn} {ln}".strip()
        return full or None

    customer_name = None
    customer_doc = None
    customer_phone = None
    company_name = None
    company_cuit = None
    reference = "Pago"

    if payment.loan_id:
        loan = db.query(Loan).get(payment.loan_id)
        if not loan or loan.company_id != current.company_id:
            raise HTTPException(status_code=404, detail="Payment no encontrado")
        if loan.customer:
            customer_name = _full_name(loan.customer)
            customer_doc = getattr(loan.customer, "dni", None)
            customer_phone = getattr(loan.customer, "phone", None)
        if loan.company:
            company_name = loan.company.name
            company_cuit = getattr(loan.company, "cuit", None)
        reference = f"Préstamo #{loan.id}"
    elif payment.purchase_id:
        purchase = db.query(Purchase).get(payment.purchase_id)
        if not purchase or purchase.company_id != current.company_id:
            raise HTTPException(status_code=404, detail="Payment no encontrado")
        if purchase.customer:
            customer_name = _full_name(purchase.customer)
            customer_doc = getattr(purchase.customer, "dni", None)
            customer_phone = getattr(purchase.customer, "phone", None)
        if purchase.company:
            company_name = purchase.company.name
            company_cuit = getattr(purchase.company, "cuit", None)
        reference = f"Compra #{purchase.id}"
    else:
        # Si no está asociado a loan/purchase, igual validamos por empresa del usuario
        if current.company and current.company.name:
            company_name = current.company.name
            company_cuit = getattr(current.company, "cuit", None)

    collector_name = payment.collector.name if payment.collector else None

    return {
        "customer_name": customer_name,
        "customer_doc": customer_doc,
        "customer_phone": customer_phone,
        "company_name": company_name,
        "company_cuit": company_cuit,
        "collector_name": collector_name,
        "reference": reference,
    }



@router.get("/{payment_id}", response_model=PaymentDetailOut)
def get_payment_detail(
    payment_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    payment = db.query(Payment).get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment no encontrado")

    ctx = _ensure_scope_and_get_context(db, payment, current)

    loan_total_amount = None
    loan_total_due = None
    installments_paid = None
    installments_overdue = None
    installments_pending = None

    if payment.loan_id:
        loan_ins = db.query(Installment).filter(Installment.loan_id == payment.loan_id).all()
        if loan_ins:
            loan_total_amount = float(sum((ins.amount or 0) for ins in loan_ins))
            loan_total_due = float(sum(max(0.0, (ins.amount or 0) - (ins.paid_amount or 0)) for ins in loan_ins))

            # 👇 usar día LOCAL AR (o podrías parametrizar tz si querés)
            today_local = datetime.now(AR_TZ).date()

            paid = over = pend = 0
            for ins in loan_ins:
                amt = float(ins.amount or 0)
                paid_amt = float(ins.paid_amount or 0)
                is_paid = paid_amt >= amt - 1e-6

                if is_paid:
                    paid += 1
                else:
                    due_dt = getattr(ins, "due_date", None)
                    # due_date podría ser aware UTC → comparar por fecha local
                    if isinstance(due_dt, datetime):
                        due_local_date = due_dt.astimezone(AR_TZ).date()
                    else:
                        # si fuera DATE puro
                        due_local_date = due_dt
                    if due_local_date and due_local_date < today_local:
                        over += 1
                    else:
                        pend += 1

            installments_paid = paid
            installments_overdue = over
            installments_pending = pend

    return PaymentDetailOut(
        id=payment.id,
        amount=float(payment.amount or 0),
        payment_date=payment.payment_date,
        loan_id=payment.loan_id,
        purchase_id=payment.purchase_id,
        payment_type=payment.payment_type,
        description=payment.description,
        customer_name=ctx["customer_name"],
        customer_doc=ctx["customer_doc"],
        customer_phone=ctx["customer_phone"],
        company_name=ctx["company_name"],
        company_cuit=ctx["company_cuit"],
        collector_name=ctx["collector_name"],
        receipt_number=getattr(payment, "receipt_number", None),
        reference=ctx["reference"],
        loan_total_amount=loan_total_amount,
        loan_total_due=loan_total_due,
        installments_paid=installments_paid,
        installments_overdue=installments_overdue,
        installments_pending=installments_pending,
    )



@router.put("/{payment_id}", response_model=PaymentDetailOut)
def update_payment(
    payment_id: int,
    body: PaymentUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    payment = db.query(Payment).get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment no encontrado")

    # Validar alcance por empresa
    _ = _ensure_scope_and_get_context(db, payment, current)

    # Solo campos no monetarios
    if body.payment_type is not None:
        payment.payment_type = body.payment_type
    if body.description is not None:
        payment.description = body.description

    db.add(payment)
    db.commit()
    db.refresh(payment)

    ctx = _ensure_scope_and_get_context(db, payment, current)

    return PaymentDetailOut(
        id=payment.id,
        amount=float(payment.amount or 0),
        payment_date=payment.payment_date,
        loan_id=payment.loan_id,
        purchase_id=payment.purchase_id,
        payment_type=payment.payment_type,
        description=payment.description,
        customer_name=ctx["customer_name"],
        customer_doc=ctx["customer_doc"],
        customer_phone=ctx["customer_phone"],
        company_name=ctx["company_name"],
        company_cuit=ctx["company_cuit"],
        collector_name=ctx["collector_name"],
        receipt_number=getattr(payment, "receipt_number", None),
        reference=ctx["reference"],
    )


class VoidPaymentRequest(BaseModel):
    reason: str | None = None


@router.post("/void/{payment_id}", status_code=200)
def void_payment(
    payment_id: int,
    body: VoidPaymentRequest | None = Body(None),
    db: Session = Depends(get_db),
    current = Depends(get_current_user),   # Employee
):
    """
    Anula un pago:
      - Marca el Payment como is_voided=True y guarda motivo/fecha/usuario.
      - Elimina allocations del pago (si existen).
      - Recalcula TODAS las cuotas del préstamo afectado (replay de pagos no anulados).
      - Actualiza estado y totales del préstamo.
    """

    try:
        # 1) Bloqueo de la fila (evita doble anulación por doble tap)
        pay = (
            db.query(Payment)
              .filter(Payment.id == payment_id)
              .with_for_update()
              .one_or_none()
        )
        if not pay:
            raise HTTPException(status_code=404, detail="Pago no encontrado")

        # 2) P0: solo prestamos (no compras)
        if pay.loan_id is None:
            raise HTTPException(status_code=400, detail="La anulación P0 aplica sólo a pagos de préstamos")

        # 3) Scope por empresa
        loan = db.query(Loan).filter(Loan.id == pay.loan_id).one_or_none()
        if not loan:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

        if loan.company_id != current.company_id:
            raise HTTPException(status_code=403, detail="No autorizado para anular pagos de otra compañía")

        # 4) Idempotencia
        if pay.is_voided:
            return {"message": "El pago ya estaba anulado", "payment_id": pay.id, "loan_id": pay.loan_id}

        # 5) Marcar como anulado + auditoría
        pay.is_voided = True
        pay.voided_at = datetime.now(timezone.utc)
        pay.void_reason = (body.reason if body else None)
        pay.voided_by_employee_id = getattr(current, "id", None)
        db.add(pay)
        db.flush()

        # 6) Eliminar allocations del pago anulado (si tu modelo las usa)
        delete_allocations_for_payment(db, pay.id)
        db.flush()

        # 7) Recalcular ledger (replay de pagos no anulados)
        recompute_ledger_for_loan(db, pay.loan_id)

        # 8) Actualizar estado y totales del préstamo (incluye total_due)
        update_status_if_fully_paid(db, loan_id=pay.loan_id, purchase_id=None)

        db.commit()

        # (Opcional) refrescar y devolver total_due actualizado
        db.refresh(loan)
        return {
            "message": "Pago anulado",
            "payment_id": pay.id,
            "loan_id": pay.loan_id,
            "loan_total_due": float(getattr(loan, "total_due", 0) or 0),
            "loan_status": getattr(loan, "status", None),
        }

    except HTTPException:
        db.rollback()
        raise
    except SQLAlchemyError as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error de base de datos al anular el pago: {e}")


# ===== NUEVO: allocations de un pago =====
@router.get("/{payment_id}/allocations")
def allocations_for_payment(
    payment_id: int = Path(..., ge=1),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Devuelve a qué cuotas se aplicó este pago y cuánto en cada una.
    """
    pay = db.query(Payment).get(payment_id)
    if not pay:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    # Validar alcance por empresa vía loan/purchase asociado
    _ = _ensure_scope_and_get_context(db, pay, current)

    q = (
        db.query(PaymentAllocation, Installment)
        .join(Installment, PaymentAllocation.installment_id == Installment.id)
        .filter(PaymentAllocation.payment_id == payment_id)
        .order_by(Installment.number.asc())
    )

    out = []
    for alloc, ins in q.all():
        out.append({
            "installment_id": ins.id,
            "installment_number": ins.number,
            "applied": float(alloc.amount_applied or 0.0),
        })
    return out


from sqlalchemy.orm import aliased
from sqlalchemy import or_

@router.get("/by-customer/{customer_id}", response_model=list[PaymentOut])
def list_payments_by_customer(
    customer_id: int,
    start_date: str | None = Query(None),
    end_date: str | None = Query(None),
    tz: str | None = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: str | None) -> bool:
        return bool(s) and len(s) == 10 and s[4] == '-' and s[7] == '-'

    start_utc = None
    end_utc_excl = None

    if _looks_like_date(start_date) and _looks_like_date(end_date):
        dfrom = date.fromisoformat(start_date) if start_date else None
        dto   = date.fromisoformat(end_date)   if end_date   else None
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(start_date)
        end_utc   = parse_iso_aware_utc(end_date)
        end_utc_excl = end_utc

    L = aliased(Loan)
    P = aliased(Purchase)
    CL = aliased(Customer)
    CP = aliased(Customer)

    q = (
        db.query(Payment)
        .outerjoin(L, Payment.loan_id == L.id)
        .outerjoin(CL, L.customer_id == CL.id)
        .outerjoin(P, Payment.purchase_id == P.id)
        .outerjoin(CP, P.customer_id == CP.id)
        .filter(Payment.is_voided.is_(False))
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .filter(or_(CL.id == customer_id, CP.id == customer_id))
    )

    # 👉 Solo el admin ve TODO. El resto, solo lo que le pertenece.
    if current.role != "admin":
        q = q.filter(
            or_(
                Payment.collector_id == current.id,  # pagos que él registró
                L.employee_id == current.id,         # préstamos que él dio
                P.employee_id == current.id,         # ventas que él dio
            )
        )

    if start_utc is not None:
        q = q.filter(Payment.payment_date >= start_utc)
    if end_utc_excl is not None:
        q = q.filter(Payment.payment_date < end_utc_excl)

    rows = q.order_by(Payment.payment_date.desc(), Payment.id.desc()).all()

    return [
        PaymentOut(
            id=p.id,
            amount=float(p.amount or 0),
            payment_date=p.payment_date,
            loan_id=p.loan_id,
            purchase_id=p.purchase_id,
            payment_type=p.payment_type,
            description=p.description,
            collector_id=p.collector_id,
            collector_name=(p.collector.name if p.collector else None),
        )
        for p in rows
    ]
