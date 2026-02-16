# app/routes/dashboard.py
from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, or_
from sqlalchemy.orm import Session, aliased

from app.database.db import get_db
from app.models.models import (
    Customer,
    Employee,
    Installment,
    Loan,
    Payment,
    PaymentAllocation,
    Purchase,
)
from app.schemas.dashboard import (
    DashboardCollectorRow,
    DashboardDayPoint,
    DashboardIssuedRow,
    DashboardKpis,
    DashboardOverdueItem,
    DashboardStatusChangeRow,
    DashboardStatusSlice,
    DashboardSummaryResponse,
    DashboardCashflowCollector,
    DashboardCashflowPoint,
)
from app.utils.auth import ensure_admin, get_current_user
from app.utils.license import ensure_company_active
from app.utils.time_windows import AR_TZ, local_dates_to_utc_window
from app.constants import InstallmentStatus


router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"],
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],
)


def _full_name(c: Customer | None) -> str | None:
    if not c:
        return None
    fn = (getattr(c, "first_name", "") or "").strip()
    ln = (getattr(c, "last_name", "") or "").strip()
    full = f"{fn} {ln}".strip()
    return full or None


@router.get("/summary", response_model=DashboardSummaryResponse)
def dashboard_summary(
    start_date: date = Query(..., description="Fecha local (YYYY-MM-DD) inclusive"),
    end_date: date = Query(..., description="Fecha local (YYYY-MM-DD) inclusive"),
    tz: Optional[str] = Query(None, description="IANA TZ (default AR)"),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ensure_admin(current)

    zone = ZoneInfo(tz) if tz else AR_TZ
    tzname = (tz or zone.key or "America/Argentina/Buenos_Aires")

    start_utc, end_utc_excl = local_dates_to_utc_window(start_date, end_date, zone)

    L = aliased(Loan)
    P = aliased(Purchase)
    CL = aliased(Customer)
    CP = aliased(Customer)

    # -------------------------
    # 1) COBRADO (pagos) en período
    # -------------------------
    payments_q = (
        db.query(Payment)
        .outerjoin(L, Payment.loan_id == L.id)
        .outerjoin(CL, L.customer_id == CL.id)
        .outerjoin(P, Payment.purchase_id == P.id)
        .outerjoin(CP, P.customer_id == CP.id)
        .filter(Payment.is_voided == False)
        .filter(
            or_(
                L.company_id == current.company_id,
                P.company_id == current.company_id,
                CL.company_id == current.company_id,
                CP.company_id == current.company_id,
            )
        )
        .filter(Payment.payment_date >= start_utc)
        .filter(Payment.payment_date < end_utc_excl)
    )

    collected_amount = float(
        payments_q.with_entities(func.coalesce(func.sum(Payment.amount), 0.0)).scalar() or 0.0
    )
    payments_count = int(payments_q.with_entities(func.count(Payment.id)).scalar() or 0)

    # -------------------------
    # 2) ESPERADO (cuotas por due_date) en período
    # -------------------------
    inst_base = (
        db.query(Installment)
        .outerjoin(L, Installment.loan_id == L.id)
        .outerjoin(P, Installment.purchase_id == P.id)
        .outerjoin(CL, L.customer_id == CL.id)
        .outerjoin(CP, P.customer_id == CP.id)
        .filter(
            or_(
                L.company_id == current.company_id,
                P.company_id == current.company_id,
                CL.company_id == current.company_id,
                CP.company_id == current.company_id,
            )
        )
        .filter(Installment.due_date >= start_utc)
        .filter(Installment.due_date < end_utc_excl)
        .filter(
            Installment.status.notin_(
                [InstallmentStatus.CANCELED.value, InstallmentStatus.REFINANCED.value]
            )
        )
    )

    expected_amount = float(
        inst_base.with_entities(func.coalesce(func.sum(Installment.amount), 0.0)).scalar() or 0.0
    )

    # -------------------------
    # 3) COBRADO aplicado a cuotas del período
    # -------------------------
    collected_for_due_amount = float(
        db.query(func.coalesce(func.sum(PaymentAllocation.amount_applied), 0.0))
        .select_from(PaymentAllocation)
        .join(Payment, PaymentAllocation.payment_id == Payment.id)
        .join(Installment, PaymentAllocation.installment_id == Installment.id)
        .outerjoin(L, Installment.loan_id == L.id)
        .outerjoin(P, Installment.purchase_id == P.id)
        .filter(Payment.is_voided == False)
        .filter(Payment.payment_date >= start_utc)
        .filter(Payment.payment_date < end_utc_excl)
        .filter(Installment.due_date >= start_utc)
        .filter(Installment.due_date < end_utc_excl)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .scalar()
        or 0.0
    )

    pending_amount = max(0.0, expected_amount - collected_for_due_amount)
    effectiveness_pct = float((collected_for_due_amount / expected_amount) * 100.0) if expected_amount > 0 else 0.0

    # -------------------------
    # 4) Serie por día (periodo seleccionado)
    # -------------------------
    inst_day = func.date(func.timezone(tzname, Installment.due_date))
    pay_day = func.date(func.timezone(tzname, Payment.payment_date))

    expected_by_day_rows = (
        inst_base.with_entities(
            inst_day.label("day"),
            func.coalesce(func.sum(Installment.amount), 0.0).label("expected"),
        )
        .group_by(inst_day)
        .order_by(inst_day)
        .all()
    )
    expected_by_day = {r.day: float(r.expected) for r in expected_by_day_rows}

    collected_by_day_rows = (
        payments_q.with_entities(
            pay_day.label("day"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("collected"),
        )
        .group_by(pay_day)
        .order_by(pay_day)
        .all()
    )
    collected_by_day = {r.day: float(r.collected) for r in collected_by_day_rows}

    all_days = sorted(set(expected_by_day.keys()) | set(collected_by_day.keys()))
    by_day = [
        DashboardDayPoint(
            date=d,
            expected_amount=float(expected_by_day.get(d, 0.0)),
            collected_amount=float(collected_by_day.get(d, 0.0)),
        )
        for d in all_days
    ]

    # -------------------------
    # 5) Performance por cobrador
    #   - Cobrado: pagos registrados (Payment.amount)
    #   - Esperado: cuotas del periodo asignadas (Installment.amount)
    #   - Efectividad: sobre cobrado registrado vs esperado (ojo: en el front vas a usar aplicado)
    # -------------------------
    # -------------------------
    # 5) Performance por cobrador (registrado vs aplicado)
    #   - expected_amount: cuotas del período (por due_date) asignadas al cobrador
    #   - registered_amount: pagos registrados en el período (por payment_date)
    #   - applied_amount: monto aplicado a cuotas del período (payment_date en período + due_date en período)
    #   - effectiveness_pct: applied_amount / expected_amount
    # -------------------------

    # 5.1) Pagos registrados (monto + conteo) por cobrador
    registered_by_collector_rows = (
        payments_q.with_entities(
            Payment.collector_id.label("collector_id"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("registered"),
            func.count(Payment.id).label("payments_count"),
        )
        .group_by(Payment.collector_id)
        .all()
    )
    registered_by_collector = {
        (int(r.collector_id) if r.collector_id is not None else 0): float(r.registered or 0.0)
        for r in registered_by_collector_rows
    }
    payments_count_by_collector = {
        (int(r.collector_id) if r.collector_id is not None else 0): int(r.payments_count or 0)
        for r in registered_by_collector_rows
    }

    # 5.2) Esperado por cobrador (cuotas del período asignadas)
    assigned_collector_id = func.coalesce(L.employee_id, P.employee_id)
    expected_by_collector_rows = (
        inst_base.with_entities(
            assigned_collector_id.label("collector_id"),
            func.coalesce(func.sum(Installment.amount), 0.0).label("expected"),
        )
        .group_by(assigned_collector_id)
        .all()
    )
    expected_by_collector = {
        (int(r.collector_id) if r.collector_id is not None else 0): float(r.expected or 0.0)
        for r in expected_by_collector_rows
    }

    # 5.3) Aplicado a cuotas del período por cobrador
    # (por payment.collector_id, y filtramos: payment_date en período + due_date en período)
    applied_by_collector_rows = (
        db.query(
            Payment.collector_id.label("collector_id"),
            func.coalesce(func.sum(PaymentAllocation.amount_applied), 0.0).label("applied"),
        )
        .select_from(PaymentAllocation)
        .join(Payment, PaymentAllocation.payment_id == Payment.id)
        .join(Installment, PaymentAllocation.installment_id == Installment.id)
        .outerjoin(L, Installment.loan_id == L.id)
        .outerjoin(P, Installment.purchase_id == P.id)
        .filter(Payment.is_voided == False)
        .filter(Payment.payment_date >= start_utc)
        .filter(Payment.payment_date < end_utc_excl)
        .filter(Installment.due_date >= start_utc)
        .filter(Installment.due_date < end_utc_excl)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .group_by(Payment.collector_id)
        .all()
    )
    applied_by_collector = {
        (int(r.collector_id) if r.collector_id is not None else 0): float(r.applied or 0.0)
        for r in applied_by_collector_rows
    }

    # 5.4) Resolver nombres
    collector_ids = (
        set(registered_by_collector.keys())
        | set(payments_count_by_collector.keys())
        | set(expected_by_collector.keys())
        | set(applied_by_collector.keys())
    )

    collectors_map = {
        e.id: e.name
        for e in db.query(Employee)
        .filter(Employee.company_id == current.company_id)
        .filter(Employee.id.in_(collector_ids))
        .all()
    }

    # 5.5) Construir response rows (con campos NUEVOS del schema)
    collectors = []
    for cid in sorted(collector_ids):
        expected = float(expected_by_collector.get(cid, 0.0))
        registered = float(registered_by_collector.get(cid, 0.0))
        applied = float(applied_by_collector.get(cid, 0.0))
        pcount = int(payments_count_by_collector.get(cid, 0))

        eff = float((applied / expected) * 100.0) if expected > 0 else 0.0

        collectors.append(
            DashboardCollectorRow(
                collector_id=cid,
                collector_name=("Sin asignar" if cid == 0 else collectors_map.get(cid)),
                expected_amount=expected,
                registered_amount=registered,
                applied_amount=applied,
                payments_count=pcount,
                effectiveness_pct=eff,
            )
        )


    # -------------------------
    # 5b) Otorgamientos (loans + purchases) en período (por start_date)
    # (aunque en el front por ahora no muestres purchases)
    # -------------------------
    loans_rows = (
        db.query(
            Loan.employee_id.label("collector_id"),
            func.count(Loan.id).label("cnt"),
            func.coalesce(func.sum(Loan.amount), 0.0).label("principal"),
            func.coalesce(func.sum(Loan.total_due), 0.0).label("total_due"),
        )
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.start_date >= start_utc)
        .filter(Loan.start_date < end_utc_excl)
        .group_by(Loan.employee_id)
        .all()
    )

    purchases_rows = (
        db.query(
            Purchase.employee_id.label("collector_id"),
            func.count(Purchase.id).label("cnt"),
            func.coalesce(func.sum(Purchase.amount), 0.0).label("principal"),
            func.coalesce(func.sum(Purchase.total_due), 0.0).label("total_due"),
        )
        .filter(Purchase.company_id == current.company_id)
        .filter(Purchase.start_date >= start_utc)
        .filter(Purchase.start_date < end_utc_excl)
        .group_by(Purchase.employee_id)
        .all()
    )

    loans_by_collector = {(int(r.collector_id) if r.collector_id is not None else 0): r for r in loans_rows}
    purchases_by_collector = {(int(r.collector_id) if r.collector_id is not None else 0): r for r in purchases_rows}
    issued_collector_ids = set(loans_by_collector.keys()) | set(purchases_by_collector.keys())

    issued_by_collector: list[DashboardIssuedRow] = []
    for cid in sorted(issued_collector_ids):
        lr = loans_by_collector.get(cid)
        pr = purchases_by_collector.get(cid)

        issued_by_collector.append(
            DashboardIssuedRow(
                collector_id=cid,
                collector_name=("Sin asignar" if cid == 0 else collectors_map.get(cid)),
                loans_count=int(getattr(lr, "cnt", 0) or 0),
                loans_principal_amount=float(getattr(lr, "principal", 0.0) or 0.0),
                loans_total_due=float(getattr(lr, "total_due", 0.0) or 0.0),
                purchases_count=int(getattr(pr, "cnt", 0) or 0),
                purchases_principal_amount=float(getattr(pr, "principal", 0.0) or 0.0),
                purchases_total_due=float(getattr(pr, "total_due", 0.0) or 0.0),
            )
        )

    # -------------------------
    # 5c) Cambios de estado (por status_changed_at) en período - SOLO LOANS
    # -------------------------
    loans_status_change_rows = (
        db.query(
            Loan.status.label("status"),
            func.count(Loan.id).label("cnt"),
            func.coalesce(func.sum(Loan.total_due), 0.0).label("total_due"),
        )
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.status_changed_at.isnot(None))
        .filter(Loan.status_changed_at >= start_utc)
        .filter(Loan.status_changed_at < end_utc_excl)
        .group_by(Loan.status)
        .order_by(func.count(Loan.id).desc())
        .all()
    )

    loan_status_changes = [
        DashboardStatusSlice(
            status=str(r.status),
            count=int(r.cnt or 0),
            total_due=float(r.total_due or 0.0),
        )
        for r in loans_status_change_rows
    ]

    loans_status_change_by_collector_rows = (
        db.query(
            Loan.employee_id.label("collector_id"),
            Loan.status.label("status"),
            func.count(Loan.id).label("cnt"),
        )
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.status_changed_at.isnot(None))
        .filter(Loan.status_changed_at >= start_utc)
        .filter(Loan.status_changed_at < end_utc_excl)
        .group_by(Loan.employee_id, Loan.status)
        .all()
    )

    change_map = defaultdict(lambda: {"canceled": 0, "refinanced": 0})
    for r in loans_status_change_by_collector_rows:
        cid = int(r.collector_id) if r.collector_id is not None else 0
        st = str(r.status or "").lower()
        if st in ("canceled", "cancelled"):
            change_map[cid]["canceled"] += int(r.cnt or 0)
        elif st == "refinanced":
            change_map[cid]["refinanced"] += int(r.cnt or 0)

    loan_status_changes_by_collector: list[DashboardStatusChangeRow] = []
    for cid in sorted(change_map.keys()):
        loan_status_changes_by_collector.append(
            DashboardStatusChangeRow(
                collector_id=cid,
                collector_name=("Sin asignar" if cid == 0 else collectors_map.get(cid)),
                canceled_count=int(change_map[cid]["canceled"]),
                refinanced_count=int(change_map[cid]["refinanced"]),
            )
        )

    # -------------------------
    # 6) Mora (al día de hoy)
    # -------------------------
    today_local = datetime.now(zone).date()
    today_start_utc, _ = local_dates_to_utc_window(today_local, today_local, zone)

    overdue_q = (
        db.query(Installment)
        .outerjoin(L, Installment.loan_id == L.id)
        .outerjoin(P, Installment.purchase_id == P.id)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .filter(Installment.due_date < today_start_utc)
        .filter(
            Installment.status.in_(
                [
                    InstallmentStatus.PENDING.value,
                    InstallmentStatus.PARTIAL.value,
                    InstallmentStatus.OVERDUE.value,
                ]
            )
        )
    )

    overdue_installments_count = int(overdue_q.with_entities(func.count(Installment.id)).scalar() or 0)
    overdue_amount = float(
        overdue_q.with_entities(
            func.coalesce(func.sum(Installment.amount - Installment.paid_amount), 0.0)
        ).scalar()
        or 0.0
    )

    overdue_customers_count = int(
        db.query(func.count(func.distinct(func.coalesce(CL.id, CP.id))))
        .select_from(Installment)
        .outerjoin(L, Installment.loan_id == L.id)
        .outerjoin(P, Installment.purchase_id == P.id)
        .outerjoin(CL, L.customer_id == CL.id)
        .outerjoin(CP, P.customer_id == CP.id)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .filter(Installment.due_date < today_start_utc)
        .filter(
            Installment.status.in_(
                [
                    InstallmentStatus.PENDING.value,
                    InstallmentStatus.PARTIAL.value,
                    InstallmentStatus.OVERDUE.value,
                ]
            )
        )
        .scalar()
        or 0
    )


        # -------------------------
    # 7) Cashflow últimos 30 días (por cobrador)
    #    - Cobrado: Payment.payment_date, Payment.collector_id
    #    - Prestado: Loan.start_date, Loan.employee_id (Loan.amount)
    # -------------------------
    today_local = datetime.now(zone).date()
    start30_local = today_local - timedelta(days=29)
    start30_utc, end30_utc_excl = local_dates_to_utc_window(start30_local, today_local, zone)

    # Cobrado por cobrador y día
    pay_day_30 = func.date(func.timezone(tzname, Payment.payment_date))
    collected_30_rows = (
        db.query(
            func.coalesce(Payment.collector_id, 0).label("collector_id"),
            pay_day_30.label("day"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("collected"),
        )
        .select_from(Payment)
        .outerjoin(L, Payment.loan_id == L.id)
        .outerjoin(P, Payment.purchase_id == P.id)
        .filter(Payment.is_voided == False)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .filter(Payment.payment_date >= start30_utc)
        .filter(Payment.payment_date < end30_utc_excl)
        .group_by(func.coalesce(Payment.collector_id, 0), pay_day_30)
        .order_by(pay_day_30)
        .all()
    )

    # Prestado por cobrador y día (SOLO loans, como pediste usar Loan.amount)
    loan_day_30 = func.date(func.timezone(tzname, Loan.start_date))
    issued_30_rows = (
        db.query(
            func.coalesce(Loan.employee_id, 0).label("collector_id"),
            loan_day_30.label("day"),
            func.coalesce(func.sum(Loan.amount), 0.0).label("issued"),
        )
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.start_date >= start30_utc)
        .filter(Loan.start_date < end30_utc_excl)
        .group_by(func.coalesce(Loan.employee_id, 0), loan_day_30)
        .order_by(loan_day_30)
        .all()
    )

    # Armamos sets de cobradores involucrados
    cashflow_collector_ids = set()
    cashflow_collector_ids |= {int(r.collector_id or 0) for r in collected_30_rows}
    cashflow_collector_ids |= {int(r.collector_id or 0) for r in issued_30_rows}
    cashflow_collector_ids.add(0)  # por las dudas, "Sin asignar"

    # Mapas: (collector_id, day) -> amount
    collected_map = {(int(r.collector_id or 0), r.day): float(r.collected or 0.0) for r in collected_30_rows}
    issued_map = {(int(r.collector_id or 0), r.day): float(r.issued or 0.0) for r in issued_30_rows}

    # Lista de días (30)
    days_30 = []
    d = start30_local
    while d <= today_local:
        days_30.append(d)
        d = d + timedelta(days=1)

    cashflow_30d_by_collector: list[DashboardCashflowCollector] = []
    for cid in sorted(cashflow_collector_ids):
        points: list[DashboardCashflowPoint] = []
        for day in days_30:
            points.append(
                DashboardCashflowPoint(
                    date=day,
                    collected_amount=float(collected_map.get((cid, day), 0.0)),
                    issued_amount=float(issued_map.get((cid, day), 0.0)),
                )
            )

        cashflow_30d_by_collector.append(
            DashboardCashflowCollector(
                collector_id=cid,
                collector_name=("Sin asignar" if cid == 0 else collectors_map.get(cid)),
                points=points,
            )
        )


    overdue_rows = (
        overdue_q.order_by(Installment.due_date.asc(), Installment.id.asc()).limit(10).all()
    )

    overdue_items: list[DashboardOverdueItem] = []
    for inst in overdue_rows:
        loan = db.get(Loan, inst.loan_id) if inst.loan_id else None
        purchase = db.get(Purchase, inst.purchase_id) if inst.purchase_id else None

        cust = (loan.customer if loan else None) or (purchase.customer if purchase else None)
        assigned_emp = (loan.employee if loan else None) or (purchase.employee if purchase else None)

        due_local = inst.due_date.astimezone(zone)
        days_overdue = max(0, (today_local - due_local.date()).days)

        overdue_items.append(
            DashboardOverdueItem(
                installment_id=inst.id,
                loan_id=inst.loan_id,
                purchase_id=inst.purchase_id,
                due_date=inst.due_date,
                amount=float(inst.amount or 0.0),
                paid_amount=float(inst.paid_amount or 0.0),
                status=str(inst.status),
                days_overdue=int(days_overdue),
                customer_id=cust.id if cust else None,
                customer_name=_full_name(cust),
                customer_phone=getattr(cust, "phone", None) if cust else None,
                assigned_collector_id=assigned_emp.id if assigned_emp else None,
                assigned_collector_name=assigned_emp.name if assigned_emp else None,
            )
        )

    # -------------------------
    # 7) Cashflow últimos 30 días (fijo)
    #    - Cobrado: Payment.payment_date
    #    - Otorgado: Loan.start_date usando Loan.amount (principal)
    # -------------------------
    start30_local = today_local - timedelta(days=29)
    start30_utc, end30_utc_excl = local_dates_to_utc_window(start30_local, today_local, zone)

    pay_day_30 = func.date(func.timezone(tzname, Payment.payment_date))
    collected_30_rows = (
        db.query(
            pay_day_30.label("day"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("collected"),
        )
        .select_from(Payment)
        .outerjoin(L, Payment.loan_id == L.id)
        .outerjoin(P, Payment.purchase_id == P.id)
        .filter(Payment.is_voided == False)
        .filter(or_(L.company_id == current.company_id, P.company_id == current.company_id))
        .filter(Payment.payment_date >= start30_utc)
        .filter(Payment.payment_date < end30_utc_excl)
        .group_by(pay_day_30)
        .order_by(pay_day_30)
        .all()
    )
    collected_30 = {r.day: float(r.collected or 0.0) for r in collected_30_rows}

    loan_day_30 = func.date(func.timezone(tzname, Loan.start_date))
    issued_30_rows = (
        db.query(
            loan_day_30.label("day"),
            func.coalesce(func.sum(Loan.amount), 0.0).label("issued"),
        )
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.start_date >= start30_utc)
        .filter(Loan.start_date < end30_utc_excl)
        .group_by(loan_day_30)
        .order_by(loan_day_30)
        .all()
    )
    issued_30 = {r.day: float(r.issued or 0.0) for r in issued_30_rows}

    cashflow_30d = []
    d = start30_local
    while d <= today_local:
        cashflow_30d.append(
            {
                "date": d,
                "collected_amount": float(collected_30.get(d, 0.0)),
                "issued_amount": float(issued_30.get(d, 0.0)),
            }
        )
        d = d + timedelta(days=1)

    resp = DashboardSummaryResponse(
        start_date=start_date,
        end_date=end_date,
        tz=tzname,
        kpis=DashboardKpis(
            expected_amount=float(expected_amount),
            collected_amount=float(collected_amount),
            collected_for_due_amount=float(collected_for_due_amount),
            pending_amount=float(pending_amount),
            effectiveness_pct=float(effectiveness_pct),
            payments_count=int(payments_count),
            overdue_customers_count=int(overdue_customers_count),
            overdue_installments_count=int(overdue_installments_count),
            overdue_amount=float(overdue_amount),
        ),
        by_day=by_day,
        collectors=collectors,
        issued_by_collector=issued_by_collector,
        loans_status=[],            # si ya no lo estás usando en el front, lo dejamos vacío
        purchases_status=[],         # idem
        overdue=overdue_items,
        loan_status_changes=loan_status_changes,
        loan_status_changes_by_collector=loan_status_changes_by_collector,
        cashflow_30d=cashflow_30d,
        cashflow_30d_by_collector=cashflow_30d_by_collector,
    )
    return resp
