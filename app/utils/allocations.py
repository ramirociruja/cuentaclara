from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import asc

from app.models.models import Installment, Payment, PaymentAllocation

EPS = 1e-6

def allocate_payment_for_loan(db: Session, loan_id: int, payment: Payment) -> None:
    """
    Registra en payment_allocations cómo se distribuye 'payment.amount'
    entre las cuotas del préstamo 'loan_id', respetando tu lógica actual
    de aplicar en orden de cuotas.

    IMPORTANTE:
    - Este helper NO toca paid_amount / is_paid de cuotas.
      Eso lo sigue haciendo tu flujo existente (p.ej. Installment.apply_payment).
    - Este helper asume que antes de llamarlo ya actualizaste las cuotas
      (o lo llamás en paralelo calculando el delta aplicado por cuota).
    """
    if payment is None or loan_id is None:
        return

    # Obtenemos las cuotas en orden
    installments = (
        db.query(Installment)
        .filter(Installment.loan_id == loan_id)
        .order_by(Installment.number.asc())
        .all()
    )

    remaining = float(payment.amount or 0.0)
    if remaining <= EPS:
        return

    # Vamos a simular "aplicar" pero SIN mutar cuotas, midiendo tope de cada una
    for ins in installments:
        if remaining <= EPS:
            break

        amount = float(ins.amount or 0.0)
        paid   = float(ins.paid_amount or 0.0)
        pending = max(amount - paid, 0.0)

        if pending <= EPS:
            continue

        take = min(pending, remaining)
        if take > EPS:
            # Registramos la allocation
            alloc = PaymentAllocation(
                payment_id=payment.id,
                installment_id=ins.id,
                amount_applied=take,
                created_at=datetime.utcnow(),
            )
            db.add(alloc)
            remaining -= take

    db.flush()


def delete_allocations_for_payment(db: Session, payment_id: int) -> None:
    """
    Elimina todas las allocations de un pago (para anulación).
    """
    if not payment_id:
        return
    db.query(PaymentAllocation).filter(
        PaymentAllocation.payment_id == payment_id
    ).delete(synchronize_session=False)
    db.flush()
