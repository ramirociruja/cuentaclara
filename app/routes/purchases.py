from typing import List, Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, HTTPException, Depends, Query, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone

from app.database.db import get_db
from app.models.models import Employee, Purchase, Customer, Installment
from app.schemas.installments import InstallmentOut
from app.schemas.purchases import PurchaseCreate, PurchaseOut
from app.utils.auth import get_current_user
from app.utils.license import ensure_company_active

from app.constants import InstallmentStatus
from app.utils.time_windows import AR_TZ


router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)]  # 🔒
)

# =========================
# CREATE
# =========================
@router.post("/", response_model=PurchaseOut, status_code=status.HTTP_201_CREATED)
def create_purchase(
    purchase: PurchaseCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Validar cliente + misma empresa
    customer = db.query(Customer).get(purchase.customer_id)
    if not customer or customer.company_id != current.company_id:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")

    zone = AR_TZ  # America/Argentina/Buenos_Aires

    # === 1) Definir start_date en HORARIO LOCAL (igual que loans) ===
    if purchase.start_date:
        sd = purchase.start_date
        if sd.tzinfo is None:
            sd = sd.replace(tzinfo=zone)
        start_local = sd.astimezone(zone)
    else:
        start_local = datetime.now(zone)

    # Guardar start_date en UTC en la Purchase
    start_date_utc = start_local.astimezone(timezone.utc)

    # === 2) Validar intervalo en días ===
    interval_days = purchase.installment_interval_days
    if interval_days is None or interval_days < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="installment_interval_days es requerido y debe ser >= 1.",
        )

    # === 3) Calcular installment_amount si no viene (igual que loans) ===
    installments_count = purchase.installments_count
    if installments_count is None or installments_count < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="installments_count es requerido y debe ser >= 1.",
        )

    installment_amount = purchase.installment_amount
    if installment_amount is None:
        installment_amount = round(purchase.amount / installments_count, 2)

    # === 4) Crear Purchase (company_id desde token) ===
    new_purchase = Purchase(
        **purchase.model_dump(exclude={"start_date", "company_id"}),
        start_date=start_date_utc,
        company_id=current.company_id,
        total_due=purchase.amount,  # saldo inicial igual al total
        installment_amount=installment_amount,
    )

    db.add(new_purchase)
    db.commit()
    db.refresh(new_purchase)

    # === 5) Crear cuotas en base a start_local ===
    today_local = datetime.now(zone).date()

    for i in range(installments_count):
        due_local = start_local + timedelta(days=interval_days * (i + 1))

        # due_date = medianoche LOCAL → UTC
        local_midnight = due_local.replace(hour=0, minute=0, second=0, microsecond=0)
        due_date_utc = local_midnight.astimezone(timezone.utc)

        is_overdue = (local_midnight.date() < today_local)
        init_status = (
            InstallmentStatus.OVERDUE.value
            if is_overdue
            else InstallmentStatus.PENDING.value
        )

        inst = Installment(
            purchase_id=new_purchase.id,
            amount=installment_amount,
            due_date=due_date_utc,
            is_paid=False,
            status=init_status,
            number=i + 1,
            paid_amount=0.0,
            is_overdue=is_overdue,
        )
        db.add(inst)

    db.commit()
    db.refresh(new_purchase)
    return new_purchase


# =========================
# GET ALL
# =========================
@router.get("/", response_model=List[PurchaseOut])
def get_all_purchases(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # scoping por empresa
    return (
        db.query(Purchase)
        .filter(Purchase.company_id == current.company_id)
        .order_by(Purchase.start_date.desc(), Purchase.id.desc())
        .all()
    )


# =========================
# GET ONE
# =========================
@router.get("/{purchase_id}", response_model=PurchaseOut)
def get_purchase(
    purchase_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    purchase = (
        db.query(Purchase)
        .filter(Purchase.id == purchase_id, Purchase.company_id == current.company_id)
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")
    return purchase


# =========================
# UPDATE (mínimo: no tocar company_id)
# =========================
@router.put("/{purchase_id}", response_model=PurchaseOut)
def update_purchase(
    purchase_id: int,
    data: PurchaseCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    purchase = (
        db.query(Purchase)
        .filter(Purchase.id == purchase_id, Purchase.company_id == current.company_id)
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")

    # WARNING: este update es "legacy": no regenera cuotas ni recalcula total_due.
    # Sólo actualiza campos permitidos.
    payload = data.model_dump(exclude={"company_id"})
    for key, value in payload.items():
        setattr(purchase, key, value)

    db.commit()
    db.refresh(purchase)
    return purchase


# =========================
# DELETE
# =========================
@router.delete("/{purchase_id}")
def delete_purchase(
    purchase_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    purchase = (
        db.query(Purchase)
        .filter(Purchase.id == purchase_id, Purchase.company_id == current.company_id)
        .first()
    )
    if not purchase:
        raise HTTPException(status_code=404, detail="Compra no encontrada")

    db.delete(purchase)
    db.commit()
    return {"message": "Compra eliminada correctamente"}


# =========================
# LIST BY CUSTOMER - USADO
# =========================
@router.get("/customer/{customer_id}", response_model=List[PurchaseOut])
def get_purchases_by_customer(
    customer_id: int,
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Validar cliente y pertenencia a empresa
    customer = db.query(Customer).get(customer_id)
    if not customer or customer.company_id != current.company_id:
        return []

    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()

    purchases = (
        db.query(Purchase)
        .filter(
            Purchase.customer_id == customer_id,
            Purchase.company_id == current.company_id,
        )
        .order_by(Purchase.start_date.desc(), Purchase.id.desc())
        .all()
    )
    if not purchases:
        return []

    out: List[PurchaseOut] = []

    for p in purchases:
        installments_out: List[InstallmentOut] = []
        for inst in p.installments:
            dd = inst.due_date
            due_local_date = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd
            is_overdue = (not inst.is_paid) and (due_local_date and due_local_date < today_local)

            installments_out.append(
                InstallmentOut(
                    id=inst.id,
                    amount=inst.amount,
                    due_date=inst.due_date,
                    status=inst.status,
                    is_paid=inst.is_paid,
                    loan_id=getattr(inst, "loan_id", None),
                    purchase_id=p.id if hasattr(inst, "purchase_id") else None,
                    is_overdue=is_overdue or bool(getattr(inst, "is_overdue", False)),
                    number=inst.number,
                    paid_amount=inst.paid_amount,
                )
            )

        out.append(
            PurchaseOut(
                id=p.id,
                customer_id=p.customer_id,
                product_name=p.product_name,
                amount=p.amount,
                total_due=p.total_due,
                installments_count=getattr(p, "installments_count", None),
                installment_amount=getattr(p, "installment_amount", None),
                installment_interval_days=getattr(p, "installment_interval_days", None),
                start_date=p.start_date,
                status=p.status,
                company_id=getattr(p, "company_id", None),
                installments_list=installments_out,
            )
        )

    return out
