from datetime import date, datetime
from pydantic import BaseModel, Field
from typing import Optional
from typing import List 

from app.schemas.installments import InstallmentOut

class LoansBase(BaseModel):
    customer_id: int
    amount: float
    start_date: date
    installments_count: int
    installment_amount: Optional[float] = None  # Puede ser calculado automáticamente
    frequency: str = Field(..., pattern="^(weekly|monthly)$")
    company_id: int  # Añadimos `company_id`


class LoansCreate(LoansBase):
    pass

class LoansUpdate(BaseModel):
    amount: Optional[float] = None
    start_date: Optional[date] = None
    installments_count: Optional[int] = None
    frequency: Optional[str] = Field(None, pattern="^(weekly|monthly)$")

class LoansOut(BaseModel):
    id: int
    customer_id: int
    amount: float
    total_due: float
    installments_count: int
    installment_amount: float
    frequency: str  # "weekly" or "monthly"
    start_date: datetime
    status: str  # "active", "paid", "defaulted"
    company_id: int
    installments: List[InstallmentOut]  # Lista de cuotas

    class Config:
        orm_mode = True

class RefinanceRequest(BaseModel):
    amount: Optional[float] = None
    installments_count: int
    start_date: date
    frequency: str = Field(..., pattern="^(weekly|monthly)$")


class LoanPaymentRequest(BaseModel):
    amount_paid: float