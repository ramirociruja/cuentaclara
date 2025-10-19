from datetime import datetime, date
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, asc

from app.models.models import Loan, Installment, Payment, PaymentAllocation

EPS = 1e-6

def _set_status_from_amounts(ins: Installment) -> None:
    """
    Setea ins.status en función de amount/paid_amount y due_date.
    Respeta strings típicos: 'paid' / 'overdue' / 'pending'.
    """
    amt = float(ins.amount or 0.0)
    paid = float(ins.paid_amount or 0.0)
    fully_paid = paid >= amt - EPS

    if fully_paid:
        ins.status = "paid"
        return

    # si no está paga, ver si venció
    due = getattr(ins, "due_date", None)
    d: date | None = None
    if isinstance(due, datetime):
        d = due.date()
    elif isinstance(due, date):
        d = due
    today = datetime.utcnow().date()
    if d and d < today:
        ins.status = "overdue"
    else:
        ins.status = "pending"


def recompute_ledger_for_loan(db: Session, loan_id: int) -> None:
    """
    Recalcula TODO el estado de cuotas del préstamo:
      - Resetea paid_amount/status de cada cuota.
      - Borra allocations previas del préstamo.
      - Aplica pagos NO anulados por fecha y crea PaymentAllocation por cada imputación.
    """
    if not loan_id:
        return

    # 1) Traer préstamo y cuotas
    loan = db.query(Loan).get(loan_id)
    if not loan:
        return

    installments = (
        db.query(Installment)
        .filter(Installment.loan_id == loan_id)
        .order_by(Installment.number.asc())
        .all()
    )

    # 2) Reset de cuotas (paid_amount y status)
    for ins in installments:
        ins.paid_amount = 0.0
        _set_status_from_amounts(ins)
    db.flush()

    # 3) Borrar allocations previas del PRÉSTAMO (no sólo de un pago)
    db.query(PaymentAllocation).filter(
        PaymentAllocation.payment_id.in_(
            db.query(Payment.id).filter(
                Payment.loan_id == loan_id,
                Payment.is_voided.is_(False)
            )
        )
    ).delete(synchronize_session=False)
    db.flush()

    # 4) Listar pagos NO anulados por fecha/id (orden estable)
    payments = (
        db.query(Payment)
        .filter(Payment.loan_id == loan_id, Payment.is_voided.is_(False))
        .order_by(asc(Payment.payment_date), asc(Payment.id))
        .all()
    )

    # 5) Aplicar pagos generando allocations
    for pay in payments:
        remaining = float(pay.amount or 0.0)
        if remaining <= EPS:
            continue

        for ins in installments:
            if remaining <= EPS:
                break

            amt = float(ins.amount or 0.0)
            paid = float(ins.paid_amount or 0.0)
            pending = max(amt - paid, 0.0)
            if pending <= EPS:
                continue

            take = min(pending, remaining)
            if take > EPS:
                # subir imputación
                ins.paid_amount = float(paid + take)
                db.add(PaymentAllocation(
                    payment_id=pay.id,
                    installment_id=ins.id,
                    amount_applied=take,
                ))
                remaining -= take
                # refrescar status de la cuota
                _set_status_from_amounts(ins)

    # 6) (Opcional) actualizar algo en Loan si tenés campos agregados
    # Ej.: loan.status global, etc. Si ya lo resolvés con otra utilidad, omití esto.

    db.flush()
