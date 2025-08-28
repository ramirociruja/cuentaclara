from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, status
from sqlalchemy import func, Float, or_, case
from sqlalchemy.orm import Session
from app.database.db import get_db
from app.models.models import Customer, Installment, Loan, Payment, Purchase
from app.schemas.installments import InstallmentDetailedOut, InstallmentListOut, InstallmentOut, InstallmentPaymentRequest, InstallmentSummaryOut, InstallmentUpdate, OverdueInstallmentOut

router = APIRouter()


EPS = Decimal("0.000001")  # tolerancia para redondeos

@router.post("/{installment_id}/pay", response_model=InstallmentOut)
def pay_installment(
    installment_id: int,
    payment_data: InstallmentPaymentRequest,
    db: Session = Depends(get_db)
):
    """
    Registra un pago para una cuota específica.
    Reglas:
      - Actualiza paid_amount, is_paid y status de forma consistente.
      - Si se cubre el total (con tolerancia), marca 'Pagada' y desactiva overdue.
      - Si hay pago parcial, 'Parcialmente Pagada'.
      - Si no hay pagos, 'Pendiente'.
    """
    installment = db.query(Installment).get(installment_id)
    if not installment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cuota no encontrada"
        )

    # --- Normalizar a Decimal para evitar problemas de flotantes (si tus montos son NUMERIC) ---
    def D(x):
        return Decimal(str(x))

    amount_to_pay = D(payment_data.amount)
    if amount_to_pay <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El monto debe ser mayor a cero"
        )

    installment_amount = D(installment.amount)
    paid_amount = D(installment.paid_amount or 0)

    # Si ya estaba completamente pagada, bloquear doble pago
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

    # Registrar el pago
    new_paid_amount = paid_amount + amount_to_pay

    # Determinar estado con tolerancia
    if new_paid_amount + EPS >= installment_amount:
        # Redondeo final para dejarla exacta al total
        new_paid_amount = installment_amount
        installment.is_paid = True
        installment.status = "Pagada"                 # <- Cadena que espera el front
        installment.is_overdue = False                # Si está paga, no cuenta como vencida
        # Opcional: fecha de pago si tenés campo
        # installment.paid_at = datetime.utcnow()
    elif new_paid_amount > 0:
        installment.is_paid = False
        installment.status = "Parcialmente Pagada"    # <- Respetar capitalización
    else:
        installment.is_paid = False
        installment.status = "Pendiente"

    # Persistir cambios en la cuota
    installment.paid_amount = Decimal(new_paid_amount)

    # Actualizar el préstamo asociado
    loan = installment.loan
    # Aseguramos no dejar negative drift
    loan.total_due = D(loan.total_due or 0) - amount_to_pay
    if loan.total_due < 0:
        loan.total_due = Decimal("0")
    # Si quedó saldado, marcarlo como pagado (ajusta el string a tu dominio)
    if loan.total_due <= EPS:
        loan.total_due = Decimal("0")
        loan.status = "paid"

    try:
        payment_row = Payment(
            amount=float(payment_data.amount),
            loan_id=installment.loan_id if installment.loan_id else None,
            purchase_id=installment.purchase_id if installment.purchase_id else None,
            payment_date=payment_data.payment_date or datetime.utcnow(),
        )
        db.add(payment_row)
    except Exception as e:
        # Si algo raro pasa al crear el Payment, hacemos rollback coherente
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error al registrar Payment: {e}")    

    db.commit()
    db.refresh(installment)
    return installment


# Get a list of all installment
@router.get("/", response_model=list[InstallmentListOut])
def get_all_installment(
    employee_id: Optional[int] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    only_pending: Optional[bool] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
):
    # Selecciono la cuota + nombre de cliente + tipo de deuda
    q = db.query(
        Installment,
       case(
    (Installment.loan_id.is_not(None), "loan"),
    else_="purchase",
).label("debt_type"),
        Customer.name.label("customer_name"),
    ).outerjoin(Loan, Installment.loan_id == Loan.id
    ).outerjoin(Purchase, Installment.purchase_id == Purchase.id
    ).outerjoin(
        Customer,
        or_(Customer.id == Loan.customer_id, Customer.id == Purchase.customer_id)
    )

    # Filtros
    if employee_id is not None:
        q = q.filter(Customer.employee_id == employee_id)

    if date_from is not None:
        q = q.filter(func.date(Installment.due_date) >= date_from)
    if date_to is not None:
        q = q.filter(func.date(Installment.due_date) <= date_to)

    if only_pending is True:
        q = q.filter(Installment.is_paid.is_(False))
    if status is not None:
        q = q.filter(Installment.status == status)

    rows = q.order_by(Installment.due_date.asc(), Installment.id.asc()).all()

    # Mapear manualmente al DTO (due_date -> date si tu modelo guarda datetime)
    out: list[InstallmentListOut] = []
    for inst, debt_type, customer_name in rows:
        out.append(InstallmentListOut(
            id=inst.id,
            amount=inst.amount,
            due_date=getattr(inst.due_date, "date", lambda: inst.due_date)(),  # conv a date si es datetime
            status=inst.status,
            is_paid=inst.is_paid,
            loan_id=inst.loan_id,
            is_overdue=inst.is_overdue,
            number=inst.number,
            paid_amount=inst.paid_amount or 0,
            customer_name=customer_name,
            debt_type=debt_type,
        ))
    return out



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
@router.get("/summary/{customer_id}")
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



@router.get("/summary", response_model=InstallmentSummaryOut)
def installments_summary(
    employee_id: Optional[int] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    db: Session = Depends(get_db),
):
    base = db.query(Installment)

    if employee_id is not None:
        base = base.outerjoin(Loan, Installment.loan_id == Loan.id) \
                   .outerjoin(Purchase, Installment.purchase_id == Purchase.id) \
                   .outerjoin(Customer, or_(Customer.id == Loan.customer_id,
                                            Customer.id == Purchase.customer_id)) \
                   .filter(Customer.employee_id == employee_id)

    if date_from is not None:
        base = base.filter(func.date(Installment.due_date) >= date_from)
    if date_to is not None:
        base = base.filter(func.date(Installment.due_date) <= date_to)

    pending_count = base.filter(Installment.is_paid.is_(False)).count()
    paid_count    = base.filter(Installment.is_paid.is_(True)).count()
    overdue_count = base.filter(
        Installment.is_paid.is_(False),
        func.date(Installment.due_date) < func.current_date()
    ).count()

    total_amount = base.with_entities(func.coalesce(func.sum(Installment.amount), 0.0).cast(Float)).scalar() or 0.0
    pending_amount = base.filter(Installment.is_paid.is_(False)) \
                         .with_entities(func.coalesce(func.sum(Installment.amount), 0.0).cast(Float)).scalar() or 0.0

    return InstallmentSummaryOut(
        pending_count=pending_count,
        paid_count=paid_count,
        overdue_count=overdue_count,
        total_amount=float(total_amount),
        pending_amount=float(pending_amount),
    )