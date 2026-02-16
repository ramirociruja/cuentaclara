from pydantic import BaseModel
from datetime import datetime, date
from typing import Optional, Literal, List

PaymentType = Literal['cash', 'transfer', 'other']

class PaymentBase(BaseModel):
    amount: float
    loan_id: Optional[int] = None
    purchase_id: Optional[int] = None
    payment_type: Optional[PaymentType] = 'cash'
    description: Optional[str] = None

class PaymentCreate(PaymentBase):
    pass

class PaymentOut(PaymentBase):
    id: int
    payment_date: datetime
    customer_id: Optional[int] = None
    customer_name: Optional[str] = None
    customer_province: Optional[str] = None
    collector_id: Optional[int] = None
    collector_name: Optional[str] = None
    is_voided: bool = False
    class Config:
        from_attributes = True  # pydantic v2 (equiv. orm_mode=True)

# 🔽 Para listados enriquecidos (si ya lo usabas, lo mantenemos tal cual)
class PaymentDetailOut(PaymentOut):
    customer_name: Optional[str] = None
    customer_doc: Optional[str] = None
    customer_phone: Optional[str] = None
    customer_province: Optional[str] = None
    company_name: Optional[str] = None
    company_cuit: Optional[str] = None
    collector_name: Optional[str] = None
    receipt_number: Optional[str] = None
    reference: Optional[str] = None

    # --- Mini resumen del préstamo (si aplica) ---
    loan_total_amount: Optional[float] = None      # suma de amounts de las cuotas
    loan_total_due: Optional[float] = None         # suma de (amount - paid_amount) >= 0
    installments_paid: Optional[int] = None        # cantidad de cuotas pagadas
    installments_overdue: Optional[int] = None     # impagas con due_date < hoy
    installments_pending: Optional[int] = None     # impagas con due_date >= hoy
    is_voided: Optional[bool] = None
    voided_at: Optional[datetime] = None
    void_reason: Optional[str] = None


class PaymentsByDay(BaseModel):
    date: date
    amount: float

class PaymentsSummaryResponse(BaseModel):
    total_amount: float
    by_day: List[PaymentsByDay] = []   # <- nuevo

# 👇 NUEVO: para editar método/nota (sin tocar monto)
class PaymentUpdate(BaseModel):
    payment_type: Optional[PaymentType] = None
    description: Optional[str] = None

# ===========================
# === BULK PAYMENTS APPLY ===
# ===========================

class BulkPaymentItemIn(BaseModel):
    loan_id: int
    amount: float
    payment_date: Optional[datetime] = None
    payment_type: Optional[PaymentType] = 'cash'
    description: Optional[str] = None
    collector_id: Optional[int] = None

class BulkPaymentApplyIn(BaseModel):
    items: List[BulkPaymentItemIn]
    all_or_nothing: bool = False

class BulkPaymentItemOut(BaseModel):
    index: int
    loan_id: int
    payment_id: Optional[int] = None
    applied: bool
    error: Optional[str] = None

class BulkPaymentApplyOut(BaseModel):
    ok: int
    failed: int
    results: List[BulkPaymentItemOut]

