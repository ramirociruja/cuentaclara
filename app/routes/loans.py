from typing import List, Optional
from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from datetime import date, datetime, timedelta, timezone
from app.database.db import get_db
from app.models.models import Loan, Installment, Customer, Company
from app.schemas.installments import InstallmentOut
from app.schemas.loans import LoansOut, LoansCreate, LoansUpdate, LoansOut, RefinanceRequest, LoanPaymentRequest
from sqlalchemy import or_
from fastapi import status

router = APIRouter()

# Crear un nuevo préstamo - USADO
@router.post("/createLoan/", response_model=LoansOut, status_code=status.HTTP_201_CREATED)
def create_loan(loan: LoansCreate, db: Session = Depends(get_db)):
    # Validar cliente
    customer = db.query(Customer).get(loan.customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    # Validar empresa
    company = db.query(Company).get(loan.company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    # Crear préstamo
    total_due = loan.amount
    start_date = loan.start_date or datetime.utcnow()
    new_loan = Loan(**loan.model_dump(exclude={"installments", "start_date"}), start_date=start_date, total_due=loan.amount)
    db.add(new_loan)
    db.commit()
    db.refresh(new_loan)

    # Crear cuotas automáticamente
    installment_amount = round(loan.amount / loan.installments_count, 2)
    for i in range(loan.installments_count):
        due_date = start_date + timedelta(weeks=i+1) if loan.frequency == "weekly" else start_date + timedelta(weeks=(i+1)*4)

        installment = Installment(
            loan_id=new_loan.id,
            amount=installment_amount,
            due_date=due_date,
            is_paid=False,
            status="Pendiente",
            number=i + 1,
            paid_amount=0.0,
            is_overdue=False  # Inicialmente no está vencida
        )
        db.add(installment)

    db.commit()
    return new_loan


# Listar préstamos por cliente - USADO
@router.get("/customer/{customer_id}", response_model=list[LoansOut])
def get_loans_by_customer(customer_id: int, db: Session = Depends(get_db)):
    loans = db.query(Loan).filter(Loan.customer_id == customer_id).all()
    
    if not loans:
        return []
    
    loan_outs = []
    for loan in loans:
        # Obtenemos las cuotas de cada préstamo
        installments_out = []
        for installment in loan.installments:
            is_overdue = installment.due_date.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc) and not installment.is_paid
            installments_out.append(InstallmentOut(
                id=installment.id,
                amount=installment.amount,
                due_date=installment.due_date,
                status=installment.status,
                is_paid=installment.is_paid,
                loan_id=loan.id,
                is_overdue=is_overdue,
                number=installment.number,  # Asegúrate de devolver el campo "number"
                paid_amount=installment.paid_amount  # Asegúrate de devolver el campo "paidAmount"
            ))
        
        loan_outs.append(LoansOut(
            id=loan.id,
            customer_id=loan.customer_id,
            amount=loan.amount,
            total_due=loan.total_due,
            installments_count=loan.installments_count,
            installment_amount=loan.installment_amount,
            frequency=loan.frequency,
            start_date=loan.start_date,
            status=loan.status,
            company_id=loan.company_id,
            installments=installments_out,
        ))
    
    return loan_outs


# Registrar un pago - USADO
@router.post("/{loan_id}/pay")
def pay_loan_installments(loan_id: int, payment: LoanPaymentRequest, db: Session = Depends(get_db)):
    loan = db.query(Loan).filter(Loan.id == loan_id).first()
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    if payment.amount_paid <= 0:
        raise HTTPException(status_code=400, detail="El monto pagado debe ser mayor a 0")

    if payment.amount_paid > loan.total_due:
        raise HTTPException(status_code=400, detail="El monto a pagar no puede ser mayor al saldo pendiente")

    unpaid_installments = (
        db.query(Installment)
        .filter(Installment.loan_id == loan_id, Installment.is_paid == False)
        .order_by(Installment.number)
        .all()
    )

    if not unpaid_installments:
        raise HTTPException(status_code=400, detail="Todas las cuotas ya están pagadas")

    remaining_amount = payment.amount_paid
    cuotas_afectadas = 0
    for installment in unpaid_installments:
        if remaining_amount <= 0:
            break
        before = remaining_amount
        remaining_amount = installment.register_payment(remaining_amount)
        if before != remaining_amount:
            cuotas_afectadas += 1

    # Restar del saldo pendiente del préstamo
    loan.total_due -= (payment.amount_paid - remaining_amount)
    loan.total_due = max(loan.total_due, 0)  # por si queda un redondeo negativo
    print(f"Saldo pendiente del préstamo después del pago: {loan.total_due}   ++++++   remaining {remaining_amount}   ++++++++ payment {payment.amount_paid}")

    # Si se pagó completamente el préstamo, cambiar el estado
    if loan.total_due == 0:
        loan.status = "paid"

    db.commit()

    return {
        "mensaje": "Pago registrado correctamente",
        "monto_pagado": payment.amount_paid - remaining_amount,
        "saldo_pendiente": loan.total_due,
        "cuotas_afectadas": cuotas_afectadas
    }

@router.get("/loans/", response_model=list[LoansOut])
def get_all_loans(db: Session = Depends(get_db), company_id: Optional[int] = None):
    query = db.query(Loan)
    if company_id:  # Filtrar préstamos por company_id
        query = query.filter(Loan.company_id == company_id)
    return query.all()

@router.get("/loans/{loan_id}", response_model=LoansOut)
def get_loan(loan_id: int, db: Session = Depends(get_db)):
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    return loan

@router.put("/loans/{loan_id}", response_model=LoansOut)
def update_loan(loan_id: int, loan_data: LoansUpdate, db: Session = Depends(get_db)):
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    # Verificar que la empresa esté presente en los datos
    if loan_data.company_id:
        company = db.query(Company).get(loan_data.company_id)
        if not company:
            raise HTTPException(status_code=404, detail="Empresa no encontrada")

    for field, value in loan_data.dict(exclude_unset=True).items():
        setattr(loan, field, value)

    db.commit()
    db.refresh(loan)
    return loan

@router.delete("/loans/{loan_id}")
def delete_loan(loan_id: int, db: Session = Depends(get_db)):
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    db.delete(loan)
    db.commit()
    return {"message": "Préstamo eliminado correctamente"}

@router.post("/loans/{loan_id}/refinance", response_model=LoansOut)
def refinance_loan(loan_id: int, data: RefinanceRequest, db: Session = Depends(get_db)):
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    # Calcular saldo restante
    unpaid_installments = db.query(Installment).filter_by(loan_id=loan_id, is_paid=False).all()
    remaining_balance = sum(inst.amount for inst in unpaid_installments)

    # Eliminar cuotas anteriores no pagadas
    for inst in unpaid_installments:
        db.delete(inst)

    # Ajustar el monto si se especifica
    final_amount = data.new_amount if data.new_amount else remaining_balance
    loan.amount = final_amount
    loan.installments = data.new_installments
    loan.start_date = date.today()

    # Crear nuevas cuotas
    new_installment_amount = round(final_amount / data.new_installments, 2)
    for i in range(data.new_installments):
        due_date = loan.start_date + timedelta(weeks=i)
        new_inst = Installment(
            loan_id=loan.id,
            amount=new_installment_amount,
            due_date=due_date,
            is_paid=False,
            status="Pendiente"
        )
        db.add(new_inst)

    db.commit()
    db.refresh(loan)
    return loan

# Listar cuotas para un préstamo
@router.get("/{loan_id}/installments", response_model=List[InstallmentOut])
def get_installments_for_loan(loan_id: int, db: Session = Depends(get_db)):
    installments = db.query(Installment).filter(Installment.loan_id == loan_id).order_by(Installment.id).all()
    if not installments:
        raise HTTPException(status_code=404, detail="No se encontraron cuotas para este préstamo")
    return installments


