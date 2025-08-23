from sqlalchemy.orm import Session
from app.models.models import Loan, Purchase, Installment

def update_status_if_fully_paid(db: Session, loan_id: int = None, purchase_id: int = None):
    """
    Checks if all installments for a loan or purchase are paid.
    If so, updates the status to 'paid'.
    """
    if loan_id:
        installments = db.query(Installment).filter_by(loan_id=loan_id).all()
        if installments and all(inst.is_paid for inst in installments):
            loan = db.query(Loan).get(loan_id)
            if loan:
                loan.status = "paid"
                db.add(loan)

    if purchase_id:
        installments = db.query(Installment).filter_by(purchase_id=purchase_id).all()
        if installments and all(inst.is_paid for inst in installments):
            purchase = db.query(Purchase).get(purchase_id)
            if purchase:
                purchase.status = "paid"
                db.add(purchase)
