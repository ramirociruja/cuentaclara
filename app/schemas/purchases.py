from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional, List, Literal

from app.schemas.installments import InstallmentOut


class PurchaseBase(BaseModel):
    customer_id: int
    product_name: str
    amount: float

    # Cantidad de cuotas
    installments_count: int = Field(..., ge=1, le=10000)

    # Monto por cuota (si no se envía, el BE puede calcularlo)
    installment_amount: Optional[float] = None

    # Intervalo en días entre cuotas (requerido para creación)
    installment_interval_days: Optional[int] = Field(None, ge=1, le=3650)

    # Fecha de inicio (opcional, si no viene el BE usa "ahora local")
    start_date: Optional[datetime] = None

    # Estado (idealmente canónico EN como en loans)
    status: Optional[str] = None

    # Se setea desde el token en el BE
    company_id: Optional[int] = None


class PurchaseCreate(PurchaseBase):
    # En CREATE lo exigimos
    installment_interval_days: int = Field(..., ge=1, le=3650)


class PurchaseOut(PurchaseBase):
    id: int
    total_due: float

    # En responses, start_date ya viene siempre
    start_date: datetime

    installments_list: List[InstallmentOut] = []

    class Config:
        from_attributes = True  # pydantic v2 (equiv. a orm_mode=True)
