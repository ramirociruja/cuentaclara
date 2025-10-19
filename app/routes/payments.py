from fastapi import APIRouter, HTTPException, Depends, Query, Path
from pydantic import BaseModel
from sqlalchemy.orm import Session, aliased
from datetime import datetime, timezone
from sqlalchemy import func, or_

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
from app.utils.status import update_status_if_fully_paid
from app.utils.auth import get_current_user
from app.utils.ledger import recompute_ledger_for_loan

# Helpers de allocations
from app.utils.allocations import (
    # allocate_payment_for_loan,  # (Se usará cuando registremos allocations en el flujo de imputación)
    delete_allocations_for_payment,
)

router = APIRouter(
    dependencies=[Depends(get_current_user)]  # 🔒 exige Bearer válido en todo el router
)

# ---------- helpers fecha ----------
def _parse_iso(dt: str | None) -> datetime | None:
    if not dt:
        return None
    try:
        return datetime.fromisoformat(dt.replace('Z', ''))
    except Exception:
        return None

def _normalize_range(date_from: str | None, date_to: str | None):
    df = _parse_iso(date_from)
    dt = _parse_iso(date_to)
    if df:
        df = df.replace(hour=0, minute=0, second=0, microsecond=0)
    if dt:
        dt = dt.replace(hour=23, minute=59, second=59, microsecond=999999)
    return df, dt
# -----------------------------------

def _parse_iso_flexible(s: str | None):
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        # Normalizamos a UTC "naive" para evitar comparar naïve vs aware
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except Exception:
        return None


@router.get("/summary", response_model=PaymentsSummaryResponse)
def get_payments_summary(
    # Aceptamos ambos esquemas de nombres
    date_from: str | None = Query(None, alias="date_from"),
    date_to: str | None = Query(None, alias="date_to"),
    start_date: str | None = Query(None, alias="start_date"),
    end_date: str | None = Query(None, alias="end_date"),
    employee_id: int | None = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Elegimos el valor presente (front actual usa date_from/date_to)
    raw_from = date_from or start_date
    raw_to   = date_to   or end_date

    start_dt = _parse_iso_flexible(raw_from)
    end_dt   = _parse_iso_flexible(raw_to)

    L  = aliased(Loan)
    P  = aliased(Purchase)
    CL = aliased(Customer)
    CP = aliased(Customer)

    q = (
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
          .outerjoin(L, Payment.loan_id == L.id)
          .outerjoin(CL, L.customer_id == CL.id)
          .outerjoin(P, Payment.purchase_id == P.id)
          .outerjoin(CP, P.customer_id == CP.id)
    )

    if start_dt is not None:
        q = q.filter(Payment.payment_date >= start_dt)
    if end_dt is not None:
        q = q.filter(Payment.payment_date <= end_dt)

    # 🔒 scope por empresa (loans o purchases)
    q = q.filter(
        or_(
            CL.company_id == current.company_id,
            CP.company_id == current.company_id,
        )
    )

    # Filtro opcional por empleado (deuda asignada)
    if employee_id is not None:
        q = q.filter(
            or_(
                CL.employee_id == employee_id,
                CP.employee_id == employee_id,
            )
        )

    total = q.scalar() or 0.0
    return PaymentsSummaryResponse(total_amount=float(total))


# Register a new payment
@router.post("/", response_model=PaymentOut)
def create_payment(
    payment: PaymentCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    if not payment.loan_id and not payment.purchase_id:
        raise HTTPException(status_code=400, detail="Debe indicar loan_id o purchase_id")

    now = datetime.utcnow()

    # Validar scoping por empresa
    if payment.loan_id:
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

    new_p = Payment(
        amount=payment.amount,
        payment_date=now,
        loan_id=payment.loan_id,
        purchase_id=payment.purchase_id,
        payment_type=payment.payment_type,
        description=payment.description,
    )

    db.add(new_p)
    db.commit()
    db.refresh(new_p)

    # Actualizar estado agregado (por préstamo o por compra)
    try:
        if new_p.loan_id:
            update_status_if_fully_paid(db, loan_id=new_p.loan_id, purchase_id=None)
            recompute_ledger_for_loan(db, new_p.loan_id)
            db.commit()
        if new_p.purchase_id:
            update_status_if_fully_paid(db, loan_id=None, purchase_id=new_p.purchase_id)
    except Exception:
        # no romper alta si la util tira error
        pass

    # NOTA IMPORTANTE:
    # La registración de allocations (PaymentAllocation) se hará en el flujo de imputación
    # real (donde aplicás el pago contra cuotas), para que el "take" quede EXACTO.
    # Cuando integremos eso, llamaremos allocate_payment_for_loan(...) en el punto correcto.

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
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    def _parse_iso(dt: str | None):
        from datetime import datetime
        if not dt:
            return None
        try:
            return datetime.fromisoformat(dt.replace("Z", "+00:00"))
        except Exception:
            return None

    start_dt = _parse_iso(start_date)
    end_dt = _parse_iso(end_date)

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
    )

    if start_dt:
        q = q.filter(Payment.payment_date >= start_dt)
    if end_dt:
        q = q.filter(Payment.payment_date <= end_dt)

    # 🔒 empresa actual
    q = q.filter(
        or_(
            CL.company_id == current.company_id,
            CP.company_id == current.company_id,
        )
    )

    if employee_id is not None:
        q = q.filter(
            or_(
                CL.employee_id == employee_id,
                CP.employee_id == employee_id,
            )
        )

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
        )
        for p in rows
    ]


def _ensure_scope_and_get_context(db: Session, payment: Payment, current: Employee):
    """
    Valida que el Payment pertenezca a la misma empresa que el usuario
    y arma contexto de cliente/empresa para el recibo.
    """
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
            customer_name = loan.customer.name
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
            customer_name = purchase.customer.name
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

    collector_name = current.name if getattr(current, "name", None) else current.email

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

    # --- Resumen de préstamo (si corresponde) ---
    loan_total_amount = None
    loan_total_due = None
    installments_paid = None
    installments_overdue = None
    installments_pending = None

    if payment.loan_id:
        # Traer cuotas del préstamo
        loan_ins = db.query(Installment).filter(Installment.loan_id == payment.loan_id).all()
        if loan_ins:
            loan_total_amount = float(sum((ins.amount or 0) for ins in loan_ins))
            loan_total_due = float(sum(max(0.0, (ins.amount or 0) - (ins.paid_amount or 0)) for ins in loan_ins))
            today = datetime.utcnow().date()
            paid = 0
            over = 0
            pend = 0
            for ins in loan_ins:
                amt = float(ins.amount or 0)
                paid_amt = float(ins.paid_amount or 0)
                is_paid = paid_amt >= amt - 1e-6
                if is_paid:
                    paid += 1
                else:
                    due_date = getattr(ins, "due_date", None)
                    if isinstance(due_date, datetime):
                        due_date = due_date.date()
                    if due_date and due_date < today:
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
    body: VoidPaymentRequest | None = None,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Anula un pago:
      - Marca el Payment como is_voided=True y guarda motivo/fecha/usuario.
      - Elimina allocations del pago (si existen).
      - Recalcula TODAS las cuotas del préstamo afectado (replay de pagos no anulados).
    """
    pay = db.query(Payment).get(payment_id)
    if not pay:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    # P0: sólo anulación de pagos de préstamos (no de compras)
    if pay.loan_id is None:
        raise HTTPException(status_code=400, detail="La anulación P0 aplica sólo a pagos de préstamos")

    if pay.is_voided:
        # idempotencia (si ya está anulado, respondemos OK igual)
        return {"message": "El pago ya estaba anulado", "payment_id": pay.id, "loan_id": pay.loan_id}

    # Marcar como anulado + auditoría básica
    pay.is_voided = True
    pay.voided_at = datetime.now(timezone.utc)
    pay.void_reason = (body.reason if body else None)
    pay.voided_by_employee_id = getattr(current, "id", None)
    db.add(pay)
    db.flush()

    # Limpiar allocations del pago anulado (si existen)
    delete_allocations_for_payment(db, pay.id)
    db.flush()

    # Recalcular cuotas y estado del préstamo por "replay" de pagos no anulados
    recompute_ledger_for_loan(db, pay.loan_id)

    db.commit()
    return {"message": "Pago anulado", "payment_id": pay.id, "loan_id": pay.loan_id}


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
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Devuelve todos los pagos (no anulados) asociados a un cliente, ya sea por Loan o Purchase,
    ordenados del más reciente al más antiguo. Scopeado por company del usuario actual.
    """
    # Aliases para joins simétricos
    L = aliased(Loan)
    P = aliased(Purchase)
    CL = aliased(Customer)  # cliente via loan
    CP = aliased(Customer)  # cliente via purchase

    start_dt = _parse_iso_flexible(start_date)
    end_dt = _parse_iso_flexible(end_date)

    q = (
        db.query(Payment)
        .outerjoin(L, Payment.loan_id == L.id)
        .outerjoin(CL, L.customer_id == CL.id)
        .outerjoin(P, Payment.purchase_id == P.id)
        .outerjoin(CP, P.customer_id == CP.id)
        .filter(Payment.is_voided.is_(False))
        # scope por empresa a través de loan/purchase
        .filter(
            or_(
                L.company_id == current.company_id,
                P.company_id == current.company_id,
            )
        )
        # filtrar por el cliente
        .filter(
            or_(
                CL.id == customer_id,
                CP.id == customer_id,
            )
        )
    )

    if start_dt is not None:
        q = q.filter(Payment.payment_date >= start_dt)
    if end_dt is not None:
        q = q.filter(Payment.payment_date <= end_dt)

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
        )
        for p in rows
    ]

