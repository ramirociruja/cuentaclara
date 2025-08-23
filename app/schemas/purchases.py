from pydantic import BaseModel
from datetime import datetime
from typing import Optional

from app.schemas.installments import InstallmentOut

class PurchaseBase(BaseModel):
    customer_id: int
    product_name: str
    amount: float
    total_due: float
    installments: int
    installment_amount: float
    frequency: str  # "weekly" or "monthly"
    status: Optional[str] = "active"
    company_id: int  # Añadimos `company_id`

class PurchaseCreate(PurchaseBase):
    pass

class PurchaseOut(BaseModel):
    id: int
    customer_id: int
    product_name: str
    amount: float
    total_due: float
    installments: int
    installment_amount: float
    frequency: str
    start_date: datetime
    status: str
    company_id: int
    installments_list: list[InstallmentOut]

    class Config:
        orm_mode = True
