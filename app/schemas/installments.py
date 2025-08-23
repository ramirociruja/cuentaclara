from pydantic import BaseModel, Field
from datetime import date, datetime
from typing import Optional

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

    class Config:
        orm_mode = True

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

class InstallmentUpdate(BaseModel):
    amount: Optional[float]
    due_date: Optional[datetime]

class InstallmentPaymentRequest(BaseModel):
    amount: float = Field(..., gt=0, description="Monto a pagar")
    payment_date: Optional[datetime] = Field(
        default_factory=datetime.utcnow,
        description="Fecha del pago (opcional, por defecto ahora)"
    )
    notes: Optional[str] = Field(
        None,
        description="Notas adicionales sobre el pago"
    )