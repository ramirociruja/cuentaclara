from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Optional, List, Literal
from datetime import date, datetime
from .installments import InstallmentOut

class LoansBase(BaseModel):
    customer_id: int
    amount: float
    installments_count: int
    installment_amount: Optional[float] = None
    installment_interval_days: Optional[int] = Field(None, ge=1, le=3650)
    start_date: Optional[datetime] = None
    status: Optional[str] = None
    company_id: Optional[int] = None
    employee_id: Optional[int] = None

    # NUEVOS
    description: Optional[str] = None
    collection_day: Optional[int] = Field(
        None, ge=1, le=7,
        description="Día de cobro ISO: 1=lunes … 7=domingo",
    )

class LoansCreate(LoansBase):
    installment_interval_days: int = Field(..., ge=1, le=3650)

class LoansUpdate(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    # ✅ SIEMPRE editables (no estructurales)
    description: Optional[str] = None
    collection_day: Optional[int] = Field(default=None, ge=1, le=7)  # 1..7 ISO

    # ✅ Estructurales (solo si NO hay pagos)
    # NO permitimos customer_id (Opción 2)
    employee_id: Optional[int] = None

    amount: Optional[float] = None
    installments_count: Optional[int] = None
    installment_amount: Optional[float] = None
    installment_interval_days: Optional[int] = Field(default=None, ge=1, le=3650)
    start_date: Optional[datetime] = None

class LoansOut(LoansBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    customer_id: int
    company_id: int
    employee_id: Optional[int] = None
    amount: float
    total_due: float
    installments_count: int
    installment_amount: float
    frequency: Optional[str] = None
    installment_interval_days: Optional[int] = None
    status: str
    description: Optional[str] = None
    collection_day: Optional[int] = None

    payments_count: int = 0
    total_paid: float = 0.0

    refinanced_from_loan_id: Optional[int] = None
    refinanced_to_loan_id: Optional[int] = None

    # ✅ agregar:
    customer_name: Optional[str] = None
    collector_name: Optional[str] = None

    # (opcional, compatibilidad front viejo)
    employee_name: Optional[str] = None
    status_changed_at: Optional[datetime] = None
    status_reason: Optional[str] = None

    # 🔹 NUEVOS (no rompen)
    payments_count: Optional[int] = None
    total_paid: Optional[float] = None
    remaining: Optional[float] = None

    # 🔹 “detalle” opcional
    installments: List[InstallmentOut] = []
    employee_name: Optional[str] = None
    
class LoanListItem(BaseModel):
    id: int
    amount: float
    total_due: float
    remaining_due: float  # saldo restante calculado (lo que vos querés mostrar como "Saldo")
    start_date: datetime
    status: str
    customer_name: str
    customer_province: Optional[str] = None
    employee_name: Optional[str] = None
    collector_id: Optional[int] = None
    collector_name: Optional[str] = None

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
    new_installments: Optional[int] = None
    reason: Optional[str] = None

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, v):
        if v is None:
            return None
        v = v.strip()
        return v or None


class CancelRequest(BaseModel):
    reason: Optional[str] = None

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, v):
        if v is None:
            return None
        v = v.strip()
        return v or None
