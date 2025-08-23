from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class PaymentBase(BaseModel):
    amount: float
    loan_id: Optional[int] = None
    purchase_id: Optional[int] = None

class PaymentCreate(PaymentBase):
    pass

class PaymentOut(PaymentBase):
    id: int
    payment_date: datetime
    payment_type: str  # "loan" or "purchase"

    class Config:
        orm_mode = True

class PaymentDetailedOut(PaymentOut):
    product_name: Optional[str] = None  # if it's a purchase
    loan_amount: Optional[float] = None  # if it's a loan
