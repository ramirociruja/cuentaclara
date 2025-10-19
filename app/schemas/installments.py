from typing_extensions import Literal
from pydantic import BaseModel, Field
from datetime import date, datetime
from typing import Optional


PaymentType = Literal['cash', 'transfer', 'other']
class InstallmentBase(BaseModel):
    amount: float
    due_date: datetime
    status: str
    is_paid: bool

class InstallmentUpdate(BaseModel):
    amount: float | None = None
    due_date: date | None = None
    status: str | None = None
    is_paid: bool | None = None

class InstallmentOut(BaseModel):
    id: int
    amount: float
    due_date: datetime       
    status: str  # Asegúrate de que "status" esté incluido
    is_paid: bool
    loan_id: int
    is_overdue: bool  # Nueva propiedad para indicar si la cuota está vencida
    number: int  # Añadir el campo "number" para la cuota
    paid_amount: float
    collection_day: Optional[int] = None

    class Config:
        orm_mode = True

class InstallmentListOut(InstallmentOut):
    customer_name: Optional[str] = None
    debt_type: Optional[str] = None  # "loan" | "purchase"
    customer_id: Optional[int] = None            # 👈 NUEVO
    customer_phone: Optional[str] = None         # 👈 NUEVO
    
class OverdueInstallmentOut(BaseModel):
    id: int
    due_date: datetime
    amount: float
    paid: bool
    customer_name: str
    debt_type: str  # "loan" or "purchase"
    product_name: Optional[str] = None
    loan_amount: Optional[float] = None

    class Config:
        orm_mode = True

class InstallmentDetailedOut(BaseModel):
    id: int
    due_date: datetime
    amount: float
    paid: bool
    customer_name: str
    debt_type: str  # "loan" or "purchase"
    product_name: Optional[str] = None
    loan_amount: Optional[float] = None

    class Config:
        orm_mode = True


class InstallmentPaymentRequest(BaseModel):
    amount: float = Field(..., gt=0, description="Monto a pagar")
    payment_date: Optional[datetime] = Field(
        default_factory=datetime.utcnow,
        description="Fecha del pago (opcional, por defecto ahora)"
    )
    payment_type: Optional[PaymentType] = None   # NUEVO
    description: Optional[str] = None            # NUEVO

class InstallmentSummaryOut(BaseModel):
    pending_count: int
    paid_count: int
    overdue_count: int
    total_amount: float
    pending_amount: float

class InstallmentPaymentResult(BaseModel):
    payment_id: int
    installment: InstallmentOut

    class Config:
        from_attributes = True  # Pydantic v2 (equiv. a orm_mode=True)