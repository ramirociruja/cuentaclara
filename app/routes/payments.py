from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from datetime import datetime
from app.database.db import get_db
from app.models.models import Payment, Loan, Purchase, Customer, Installment
from sqlalchemy import or_
from app.schemas.payments import PaymentCreate, PaymentOut, PaymentDetailedOut
from app.utils.status import update_status_if_fully_paid


router = APIRouter()

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
def get_all_payments(db: Session = Depends(get_db)):
    return db.query(Payment).all()

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