from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from app.database.db import get_db
from app.models.models import Company, Employee, Purchase, Customer, Installment
from app.schemas.installments import InstallmentOut
from app.schemas.purchases import PurchaseCreate, PurchaseOut
from app.utils.auth import get_current_user
from app.utils.license import ensure_company_active

router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)]  # 🔒
)

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
def get_purchases_by_customer(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Validar que el cliente exista y pertenezca a la misma empresa
    customer = db.query(Customer).get(customer_id)
    if not customer or customer.company_id != current.company_id:
        return []

    purchases = (
        db.query(Purchase)
          .filter(
              Purchase.customer_id == customer_id,
              Purchase.company_id == current.company_id,
          )
          .all()
    )
    if not purchases:
        return []

    out: list[PurchaseOut] = []
    now = datetime.now(timezone.utc)

    for p in purchases:
        installments_out: list[InstallmentOut] = []
        for inst in p.installments:
            # usar paid_amount (snake_case) y calcular is_overdue de forma segura
            is_overdue_calc = (inst.due_date < now) and (not inst.is_paid)
            installments_out.append(InstallmentOut(
                id=inst.id,
                amount=inst.amount,
                due_date=inst.due_date,
                status=inst.status,
                is_paid=inst.is_paid,
                is_overdue=is_overdue_calc or bool(getattr(inst, "is_overdue", False)),
                number=inst.number,
                paid_amount=inst.paid_amount,   # ✅ snake_case correcto
            ))

        out.append(PurchaseOut(
            id=p.id,
            customer_id=p.customer_id,
            product_name=p.product_name,
            amount=p.amount,
            total_due=p.total_due,
            installments=p.installments_count,     # ✅ usar *_count del modelo
            installment_amount=p.installment_amount,
            frequency=p.frequency,
            start_date=p.start_date,
            status=p.status,
            company_id=p.company_id,
            installments_list=installments_out,
        ))

    return out

