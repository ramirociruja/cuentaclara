# app/schemas/dashboard.py
from __future__ import annotations

from datetime import date, datetime
from pydantic import BaseModel
from typing import List, Optional


class DashboardKpis(BaseModel):
    expected_amount: float
    collected_amount: float
    collected_for_due_amount: float
    pending_amount: float
    effectiveness_pct: float
    payments_count: int

    overdue_customers_count: int
    overdue_installments_count: int
    overdue_amount: float


class DashboardDayPoint(BaseModel):
    date: date
    expected_amount: float
    collected_amount: float

class DashboardCashflowPoint(BaseModel):
    date: date
    collected_amount: float     # pagos registrados (payment_date)
    issued_amount: float        # préstamos otorgados (Loan.amount por start_date)


class DashboardCollectorRow(BaseModel):
    collector_id: int
    collector_name: str | None = None

    expected_amount: float

    # NUEVO: separar registrado vs aplicado
    registered_amount: float
    applied_amount: float
    payments_count: int

    # efectividad SIEMPRE contra aplicado/esperado
    effectiveness_pct: float


class DashboardIssuedRow(BaseModel):
    collector_id: int
    collector_name: str | None = None

    loans_count: int
    loans_principal_amount: float
    loans_total_due: float

    purchases_count: int
    purchases_principal_amount: float
    purchases_total_due: float


class DashboardStatusSlice(BaseModel):
    status: str
    count: int
    total_due: float


class DashboardOverdueItem(BaseModel):
    installment_id: int
    loan_id: int | None = None
    purchase_id: int | None = None

    due_date: datetime
    amount: float
    paid_amount: float
    status: str
    days_overdue: int

    customer_id: int | None = None
    customer_name: str | None = None
    customer_phone: str | None = None

    assigned_collector_id: int | None = None
    assigned_collector_name: str | None = None


class DashboardSummaryResponse(BaseModel):
    start_date: date
    end_date: date
    tz: str

    kpis: DashboardKpis
    by_day: List[DashboardDayPoint]

    # MODIFICADO
    collectors: List[DashboardCollectorRow]

    # NUEVO: tendencia 30 días
    cashflow_30d: List[DashboardCashflowPoint]
    cashflow_30d_by_collector: list[DashboardCashflowCollector] = []

    issued_by_collector: List[DashboardIssuedRow]
    loans_status: List[DashboardStatusSlice]
    purchases_status: List[DashboardStatusSlice]

    overdue: List[DashboardOverdueItem]



class DashboardStatusChangeRow(BaseModel):
    collector_id: int
    collector_name: str | None = None
    canceled_count: int = 0
    refinanced_count: int = 0

class DashboardCashflowPoint(BaseModel):
    date: date
    collected_amount: float
    issued_amount: float

class DashboardCashflowCollector(BaseModel):
    collector_id: int
    collector_name: Optional[str] = None
    points: List[DashboardCashflowPoint]
