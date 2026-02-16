from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
from datetime import date, datetime

# ---------- Base (entrada) ----------
class CustomerBase(BaseModel):
    first_name: str = Field(..., min_length=1)
    last_name:  str = Field(..., min_length=0)
    dni: Optional[str] = Field(None, min_length=7)
    address: str
    phone: str
    email: Optional[str] = None 
    province: Optional[str] = None

    # 👇 Para P0-B: estos campos NO deben ser obligatorios en la entrada
    company_id: Optional[int] = None   # lo impone el backend desde el token
    employee_id: Optional[int] = None  # opcional asignación

    @field_validator('dni')
    @classmethod
    def dni_must_be_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.isalnum():
            raise ValueError('DNI debe contener solo caracteres alfanuméricos')
        return v.upper() if v is not None else v

    @field_validator('email')
    @classmethod
    def empty_email_to_none(cls, v):
        v = (v or "").strip()
        return v if v else None

# ---------- Crear ----------
class CustomerCreate(CustomerBase):
    # sin extras: company_id viene del token en el router
    pass

# ---------- Actualizar (todo opcional) ----------
class CustomerUpdate(BaseModel):
    first_name: Optional[str] = None
    last_name:  Optional[str] = None
    dni: Optional[str] = Field(None, min_length=7)
    address: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    province: Optional[str] = None
    employee_id: Optional[int] = None

    @field_validator('dni')
    @classmethod
    def dni_must_be_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.isalnum():
            raise ValueError('DNI debe contener solo caracteres alfanuméricos')
        return v.upper() if v is not None else v

# ---------- Salida ----------
class CustomerOut(BaseModel):
    id: int
    first_name: str
    last_name: str
    dni: Optional[str] = None
    address: str
    phone: str
    email: Optional[str] = None
    province: Optional[str] = None
    employee_id: Optional[int] = None
    company_id: int
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True  # (pydantic v2)



class CustomerDashboardOut(BaseModel):
    customer_id: int

    total_due: float               # saldo total del cliente (sum loan.total_due de loans efectivos)
    active_loans_count: int        # loans efectivos con saldo > 0
    loans_total_count: int         # total loans del cliente (incluye cancel/refinanced/paid)

    overdue_installments_count: int
    overdue_amount: float          # suma de saldos vencidos (amount - paid_amount)

    next_due_date: Optional[date] = None
    next_due_amount: Optional[float] = None  # saldo de la próxima cuota (amount - paid_amount)




class CustomerLoanRowOut(BaseModel):
    loan_id: int
    status: Optional[str] = None

    amount: float = 0.0
    total_due: float = 0.0  # saldo actual (Loan.total_due)

    installments_count: Optional[int] = None
    installment_amount: Optional[float] = None
    installment_interval_days: Optional[int] = None
    start_date: Optional[str] = None  # ISO (opcional)

    collector_id: Optional[int] = None
    collector_name: Optional[str] = None
    description: Optional[str] = None

    overdue_installments_count: int = 0
    overdue_amount: float = 0.0

    next_due_date: Optional[date] = None
    next_due_amount: Optional[float] = None

class CustomerLoansOut(BaseModel):
    customer_id: int
    active_only: bool
    total_count: int
    total_due: float
    overdue_amount: float
    overdue_installments_count: int
    loans: List[CustomerLoanRowOut]