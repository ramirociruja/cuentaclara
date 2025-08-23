from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from app.database.db import get_db
from app.models.models import Company, Purchase, Customer, Installment
from app.schemas.installments import InstallmentOut
from app.schemas.purchases import PurchaseCreate, PurchaseOut

router = APIRouter()

# Crear una nueva compra
@router.post("/", response_model=PurchaseOut)
def create_purchase(purchase: PurchaseCreate, db: Session = Depends(get_db)):
    # Validar existencia de cliente
    customer = db.query(Customer).get(purchase.customer_id)
    if not customer:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    # Validar existencia de empresa
    company = db.query(Company).get(purchase.company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    # Crear la compra
    start_date = purchase.start_date or datetime.utcnow()
    new_purchase = Purchase(**purchase.dict(), start_date=start_date)
    db.add(new_purchase)
    db.commit()
    db.refresh(new_purchase)

    # Crear cuotas automáticamente
    for i in range(purchase.installments):
        delta = timedelta(weeks=i) if purchase.frequency == "weekly" else timedelta(weeks=i * 4)
        due_date = start_date + delta

        new_installment = Installment(
            purchase_id=new_purchase.id,
            amount=purchase.installment_amount,
            due_date=due_date,
            is_paid=False,
            status="Pendiente",
            number=i + 1,
            paidAmount=0.0
        )
        db.add(new_installment)

    db.commit()
    return new_purchase


# Obtener todas las compras
@router.get("/", response_model=list[PurchaseOut])
def get_all_purchases(db: Session = Depends(get_db)):
    return db.query(Purchase).all()

# Obtener una compra por ID
@router.get("/{purchase_id}", response_model=PurchaseOut)
def get_purchase(purchase_id: int, db: Session = Depends(get_db)):
    purchase = db.query(Purchase).get(purchase_id)
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")
    return purchase

# Actualizar una compra
@router.put("/{purchase_id}", response_model=PurchaseOut)
def update_purchase(purchase_id: int, data: PurchaseCreate, db: Session = Depends(get_db)):
    purchase = db.query(Purchase).get(purchase_id)
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")

    for key, value in data.dict().items():
        setattr(purchase, key, value)

    db.commit()
    db.refresh(purchase)
    return purchase

# Eliminar una compra
@router.delete("/{purchase_id}")
def delete_purchase(purchase_id: int, db: Session = Depends(get_db)):
    purchase = db.query(Purchase).get(purchase_id)
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")

    db.delete(purchase)
    db.commit()
    return {"message": "Compra eliminada correctamente"}

# Obtener todas las compras de un cliente específico - USADO
@router.get("/customer/{customer_id}", response_model=list[PurchaseOut])
def get_purchases_by_customer(customer_id: int, db: Session = Depends(get_db)):
    purchases = db.query(Purchase).filter(Purchase.customer_id == customer_id).all()

    if not purchases:
        return []

    purchase_outs = []
    for purchase in purchases:
        installments_out = []
        for installment in purchase.installments:
            is_overdue = installment.due_date < datetime.now(timezone.utc) and not installment.is_paid
            installments_out.append(InstallmentOut(
                id=installment.id,
                amount=installment.amount,
                due_date=installment.due_date,
                status=installment.status,
                is_paid=installment.is_paid,
                is_overdue=is_overdue,
                number=installment.number,
                paidAmount=installment.paidAmount
            ))

        purchase_outs.append(PurchaseOut(
            id=purchase.id,
            customer_id=purchase.customer_id,
            product_name=purchase.product_name,
            amount=purchase.amount,
            total_due=purchase.total_due,
            installments=purchase.installments,
            installment_amount=purchase.installment_amount,
            frequency=purchase.frequency,
            start_date=purchase.start_date,
            status=purchase.status,
            company_id=purchase.company_id,
            installments_list=installments_out
        ))

    return purchase_outs

