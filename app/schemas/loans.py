from pydantic import BaseModel, Field
from typing import Optional, List, Literal
from datetime import date, datetime
from .installments import InstallmentOut

class LoansBase(BaseModel):
    customer_id: int
    amount: float
    installments_count: int
    installment_amount: Optional[float] = None
    frequency: str                      # "weekly" | "monthly" (como ya usás)
    start_date: Optional[datetime] = None
    status: Optional[str] = None
    company_id: int

    # NUEVOS
    description: Optional[str] = None
    collection_day: Optional[int] = Field(
        None, ge=1, le=7,
        description="Día de cobro ISO: 1=lunes … 7=domingo",
    )

class LoansCreate(LoansBase):
    pass

class LoansUpdate(BaseModel):
    amount: Optional[float] = None
    installments_count: Optional[int] = None
    installment_amount: Optional[float] = None
    frequency: Optional[str] = None
    start_date: Optional[datetime] = None
    status: Optional[str] = None
    company_id: Optional[int] = None

    # NUEVOS
    description: Optional[str] = None
    collection_day: Optional[int] = Field(None, ge=1, le=7)

class LoansOut(LoansBase):
    id: int
    total_due: float
    installments: List[InstallmentOut] = []
    company_id: Optional[int] = None

    class Config:
        from_attributes = True  # pydantic v2 (equiv. a orm_mode=True)
class LoanListItem(BaseModel):
    id: int
    amount: float
    start_date: datetime
    customer_name: str
    customer_province: Optional[str] = None

class LoansByDay(BaseModel):
    date: date
    amount: float
    count: int
class LoansSummaryResponse(BaseModel):
    count: int
    amount: float
    by_day: List[LoansByDay] = []   # <- nuevo
    customer_province: Optional[str] = None

class LoanPaymentRequest(BaseModel):
    amount_paid: float
    payment_type: Optional[Literal["cash", "transfer", "other"]] = None
    description: Optional[str] = None

class RefinanceRequest(BaseModel):
    new_amount: Optional[float] = None
    new_installments: int
