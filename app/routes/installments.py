from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, status
from sqlalchemy import or_
from sqlalchemy.orm import Session
from app.database.db import get_db
from app.models.models import Customer, Installment, Loan, Purchase
from app.schemas.installments import InstallmentDetailedOut, InstallmentOut, InstallmentPaymentRequest, InstallmentUpdate, OverdueInstallmentOut

router = APIRouter()


## Registrar un pago para una cuota específica - USADO
@router.post("/{installment_id}/pay", response_model=InstallmentOut)
def pay_installment(
    installment_id: int,
    payment_data: InstallmentPaymentRequest,
    db: Session = Depends(get_db)
):
    """
    Registra un pago para una cuota específica
    """
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cuota no encontrada"
        )

    # Validaciones
    if installment.is_paid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esta cuota ya está pagada completamente"
        )

    if payment_data.amount <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El monto debe ser mayor a cero"
        )

    remaining_amount = installment.amount - installment.paid_amount
    if payment_data.amount > remaining_amount:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El monto excede el saldo pendiente. Máximo a pagar: {remaining_amount}"
        )

    # Registrar el pago
    installment.paid_amount += payment_data.amount
    installment.is_paid = installment.paid_amount >= installment.amount

    # Actualizar el préstamo asociado
    loan = installment.loan
    loan.total_due -= payment_data.amount

    if loan.total_due == 0:
        loan.status = "paid"

    db.commit()
    db.refresh(installment)

    return installment


# Get a list of all installment
@router.get("/installment/", response_model=list[InstallmentOut])
def get_all_installment(db: Session = Depends(get_db)):
    return db.query(Installment).all()

# Get all installment for a specific loan
@router.get("/installment/loan/{loan_id}", response_model=list[InstallmentOut])
def get_installment_by_loan(loan_id: int, db: Session = Depends(get_db)):
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    return db.query(Installment).filter_by(loan_id=loan_id).all()

# Get a single installment by its ID
@router.get("/installment/{installment_id}", response_model=InstallmentOut)
def get_installment(installment_id: int, db: Session = Depends(get_db)):
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")
    return installment

# Update an installment (e.g., amount, due_date, status)
@router.put("/installment/{installment_id}", response_model=InstallmentOut)
def update_installment(installment_id: int, data: InstallmentUpdate, db: Session = Depends(get_db)):
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")

    for field, value in data.dict(exclude_unset=True).items():
        setattr(installment, field, value)

    db.commit()
    db.refresh(installment)
    return installment

# Delete an installment
@router.delete("/installment/{installment_id}")
def delete_installment(installment_id: int, db: Session = Depends(get_db)):
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")
    db.delete(installment)
    db.commit()
    return {"message": "Cuota eliminada correctamente"}

# Mark an installment as paid
@router.put("/installment/{installment_id}/pay")
def mark_installment_as_paid(installment_id: int, db: Session = Depends(get_db)):
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(status_code=404, detail="Cuota no encontrada")

    if installment.is_paid:
        return {"message": "La cuota ya estaba marcada como pagada"}

    installment.is_paid = True
    installment.status = "Pagada"
    db.commit()
    return {"message": "Cuota marcada como pagada"}


# Get detailed list of overdue installment
@router.get("/installment/overdue/detailed", response_model=list[OverdueInstallmentOut])
def get_overdue_installment_detailed(db: Session = Depends(get_db)):
    today = datetime.utcnow()
    installment = db.query(Installment).filter(
        Installment.due_date < today,
        Installment.paid == False
    ).all()

    results = []

    for inst in installment:
        data = {
            "id": inst.id,
            "due_date": inst.due_date,
            "amount": inst.amount,
            "paid": inst.paid,
            "customer_name": "",
            "debt_type": "loan" if inst.loan_id else "purchase",
            "product_name": None,
            "loan_amount": None
        }

        if inst.loan_id:
            loan = db.query(Loan).get(inst.loan_id)
            if loan:
                data["customer_name"] = loan.customer.name
                data["loan_amount"] = loan.amount

        elif inst.purchase_id:
            purchase = db.query(Purchase).get(inst.purchase_id)
            if purchase:
                data["customer_name"] = purchase.customer.name
                data["product_name"] = purchase.product_name

        results.append(data)

    return results


# Get detailed list of paid installment
@router.get("/installment/paid/detailed", response_model=list[InstallmentDetailedOut])
def get_paid_installment_detailed(db: Session = Depends(get_db)):
    installment = db.query(Installment).filter(
        Installment.paid == True
    ).all()

    results = []

    for inst in installment:
        data = {
            "id": inst.id,
            "due_date": inst.due_date,
            "amount": inst.amount,
            "paid": inst.paid,
            "customer_name": "",
            "debt_type": "loan" if inst.loan_id else "purchase",
            "product_name": None,
            "loan_amount": None
        }

        if inst.loan_id:
            loan = db.query(Loan).get(inst.loan_id)
            if loan:
                data["customer_name"] = loan.customer.name
                data["loan_amount"] = loan.amount

        elif inst.purchase_id:
            purchase = db.query(Purchase).get(inst.purchase_id)
            if purchase:
                data["customer_name"] = purchase.customer.name
                data["product_name"] = purchase.product_name

        results.append(data)

    return results


@router.get("/installment/paid/by-customer/{customer_id}", response_model=list[InstallmentDetailedOut])
def get_paid_installment_by_customer(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    installment = db.query(Installment).filter(
        Installment.paid == True,
        or_(
            Installment.loan_id.in_(
                db.query(Loan.id).filter(Loan.customer_id == customer_id)
            ),
            Installment.purchase_id.in_(
                db.query(Purchase.id).filter(Purchase.customer_id == customer_id)
            )
        )
    ).all()

    results = []

    for inst in installment:
        data = {
            "id": inst.id,
            "due_date": inst.due_date,
            "amount": inst.amount,
            "paid": inst.paid,
            "customer_name": customer.name,
            "debt_type": "loan" if inst.loan_id else "purchase",
            "product_name": None,
            "loan_amount": None
        }

        if inst.loan_id:
            loan = db.query(Loan).get(inst.loan_id)
            if loan:
                data["loan_amount"] = loan.amount

        elif inst.purchase_id:
            purchase = db.query(Purchase).get(inst.purchase_id)
            if purchase:
                data["product_name"] = purchase.product_name

        results.append(data)

    return results


@router.get("/overdue/by-customer/{customer_id}", response_model=list[InstallmentOut])
def get_overdue_installment_by_customer(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    today = datetime.utcnow()

    overdue_installment = db.query(Installment).filter(
        Installment.due_date < today,
        Installment.status != "paid",
        or_(
            Installment.loan.has(Loan.customer_id == customer_id),
            Installment.purchase.has(Purchase.customer_id == customer_id)
        )
    ).all()

    return overdue_installment

# Get the next installment for a customer
@router.get("/next/by-customer/{customer_id}", response_model=Optional[InstallmentOut])
def get_next_installment_by_customer(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    today = datetime.utcnow()

    next_installment = db.query(Installment).filter(
        Installment.due_date >= today,
        Installment.status != "paid",
        or_(
            Installment.loan.has(Loan.customer_id == customer_id),
            Installment.purchase.has(Purchase.customer_id == customer_id)
        )
    ).order_by(Installment.due_date.asc()).first()

    return next_installment


# Get all overdue installment for a customer
@router.get("/by-customer/{customer_id}/overdue", response_model=list[InstallmentOut])
def get_overdue_installment_by_customer(customer_id: int, db: Session = Depends(get_db)):
    # Make sure the customer exists
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    today = datetime.utcnow()

    overdue_installment = db.query(Installment).join(Loan, isouter=True).join(Purchase, isouter=True).filter(
        or_(
            Loan.customer_id == customer_id,
            Purchase.customer_id == customer_id
        ),
        Installment.status == "overdue",
        Installment.due_date < today
    ).all()

    return overdue_installment


#Cuotas pagads y no pagads por un cliente
@router.get("/installment/history/{customer_id}", response_model=list[InstallmentOut])
def get_installment_history(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    installment = db.query(Installment).filter(
        or_(
            Installment.loan_id.in_([loan.id for loan in customer.loan]),
            Installment.purchase_id.in_([purchase.id for purchase in customer.purchases])
        )
    ).order_by(Installment.due_date).all()

    return installment

#Resumen por cliente
@router.get("/installment/summary/{customer_id}")
def get_debt_summary(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    today = datetime.utcnow()

    all_installment = db.query(Installment).filter(
        or_(
            Installment.loan_id.in_([loan.id for loan in customer.loan]),
            Installment.purchase_id.in_([purchase.id for purchase in customer.purchases])
        )
    ).all()

    total_due = sum(inst.amount for inst in all_installment if not inst.paid)
    overdue = sum(inst.amount for inst in all_installment if not inst.paid and inst.due_date < today)
    upcoming = sum(inst.amount for inst in all_installment if not inst.paid and inst.due_date >= today)

    return {
        "total_due": total_due,
        "overdue": overdue,
        "upcoming": upcoming
    }

#Modificación manual del monto de la cuota

@router.put("/installment/{installment_id}", response_model=InstallmentOut)
def update_installment(installment_id: int, updated_data: InstallmentUpdate, db: Session = Depends(get_db)):
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(status_code=404, detail="Installment not found")

    if updated_data.amount is not None:
        installment.amount = updated_data.amount
    if updated_data.due_date is not None:
        installment.due_date = updated_data.due_date

    db.commit()
    db.refresh(installment)
    return installment




# Obtener el número de cuotas vencidas para un cliente - USADO
@router.get("/by-customer/{customer_id}/overdue-count", response_model=int)
def get_overdue_installment_count_by_customer(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).get(customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")

    today = datetime.utcnow()

    overdue_installment_count = db.query(Installment).join(Loan, isouter=True).join(Purchase, isouter=True).filter(
        or_(
            Loan.customer_id == customer_id,
            Purchase.customer_id == customer_id
        ),
        Installment.due_date < today,
        Installment.is_paid == False  # Estado de impago
    ).count()

    return overdue_installment_count