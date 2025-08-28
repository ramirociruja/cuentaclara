from fastapi import APIRouter, HTTPException, Depends, Query
from sqlalchemy.orm import Session
from datetime import datetime
from app.database.db import get_db
from app.models.models import Payment, Loan, Purchase, Customer, Installment
from sqlalchemy import func, or_
from app.schemas.payments import PaymentCreate, PaymentOut, PaymentDetailedOut, PaymentsSummaryResponse
from app.utils.status import update_status_if_fully_paid


router = APIRouter()

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

@router.get("/summary", response_model=PaymentsSummaryResponse)
def payments_summary(
    employee_id: int | None = Query(None),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    db: Session = Depends(get_db),
):
    df, dt = _normalize_range(date_from, date_to)

    q = db.query(func.coalesce(func.sum(Payment.amount), 0.0))

    if df is not None:
        q = q.filter(Payment.payment_date >= df)
    if dt is not None:
        q = q.filter(Payment.payment_date <= dt)

    if employee_id is not None:
        q = (
            q.join(Loan, Payment.loan_id == Loan.id)
             .join(Customer, Loan.customer_id == Customer.id)
             .filter(Customer.employee_id == employee_id)
        )

    total = q.scalar() or 0.0
    return PaymentsSummaryResponse(total_amount=float(total))

# Register a new payment
@router.post("/", response_model=PaymentOut)
def create_payment(payment: PaymentCreate, db: Session = Depends(get_db)):
    if not payment.loan_id and not payment.purchase_id:
        raise HTTPException(status_code=400, detail="Debe especificar loan_id o purchase_id")

    if payment.loan_id:
        loan = db.query(Loan).get(payment.loan_id)
        if not loan:
            raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    if payment.purchase_id:
        purchase = db.query(Purchase).get(payment.purchase_id)
        if not purchase:
            raise HTTPException(status_code=404, detail="Compra no encontrada")

    new_payment = Payment(
        amount=payment.amount,
        loan_id=payment.loan_id,
        purchase_id=payment.purchase_id,
        payment_date=datetime.utcnow()
    )

    db.add(new_payment)
    db.commit()
    db.refresh(new_payment)


    # ✅ Check if everything is paid and update status
    update_status_if_fully_paid(db, loan_id=payment.loan_id, purchase_id=payment.purchase_id)
    db.commit()

    # Mark the next installment as pending
    mark_next_installment_pending(db, loan_id=payment.loan_id, purchase_id=payment.purchase_id)

    return new_payment


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
def get_all_payments(
    db: Session = Depends(get_db),
    employee_id: int | None = Query(None),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
):
    df, dt = _normalize_range(date_from, date_to)

    q = db.query(Payment)

    if df is not None:
        q = q.filter(Payment.payment_date >= df)
    if dt is not None:
        q = q.filter(Payment.payment_date <= dt)

    if employee_id is not None:
        q = (
            q.join(Loan, Payment.loan_id == Loan.id)
             .join(Customer, Loan.customer_id == Customer.id)
             .filter(Customer.employee_id == employee_id)
        )

    rows = q.order_by(Payment.payment_date.desc()).all()
    out: list[PaymentOut] = []
    for p in rows:
        ptype = "loan" if p.loan_id else ("purchase" if p.purchase_id else "unknown")
        out.append(PaymentOut(
            id=p.id,
            amount=float(p.amount or 0),
            payment_date=p.payment_date,
            loan_id=p.loan_id,
            purchase_id=p.purchase_id,
            payment_type=ptype,
        ))
    return out


# (tus otras rutas siguen igual: by-customer, detailed, etc.)

# Get one payment by ID
@router.get("/{payment_id}", response_model=PaymentOut)
def get_payment(payment_id: int, db: Session = Depends(get_db)):
    payment = db.query(Payment).get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    return payment

# Delete a payment
@router.delete("/{payment_id}")
def delete_payment(payment_id: int, db: Session = Depends(get_db)):
    payment = db.query(Payment).get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    db.delete(payment)
    db.commit()
    return {"message": "Pago eliminado correctamente"}



# Get all payments for a specific customer
@router.get("/by-customer/{customer_id}", response_model=list[PaymentOut])
def get_payments_by_customer(customer_id: int, db: Session = Depends(get_db)):
    # Verificamos que el cliente exista
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    payments = db.query(Payment).join(Loan, isouter=True).join(Purchase, isouter=True).filter(
        or_(
            Loan.customer_id == customer_id,
            Purchase.customer_id == customer_id
        )
    ).all()

    return payments

@router.get("/payments/detailed", response_model=list[PaymentDetailedOut])
def get_detailed_payments(db: Session = Depends(get_db)):
    payments = db.query(Payment).all()
    results = []

    for payment in payments:
        data = {
            "id": payment.id,
            "amount": payment.amount,
            "payment_date": payment.payment_date,
            "loan_id": payment.loan_id,
            "purchase_id": payment.purchase_id,
            "payment_type": "loan" if payment.loan_id else "purchase",
            "product_name": None,
            "loan_amount": None,
        }

        if payment.purchase_id:
            purchase = db.query(Purchase).get(payment.purchase_id)
            if purchase:
                data["product_name"] = purchase.product_name

        if payment.loan_id:
            loan = db.query(Loan).get(payment.loan_id)
            if loan:
                data["loan_amount"] = loan.amount

        results.append(data)

    return results