from typing import List, Optional
from zoneinfo import ZoneInfo
from fastapi import APIRouter, HTTPException, Depends, Query, status
from sqlalchemy.orm import Session
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import func, literal, or_, and_, case

from app.database.db import get_db
from app.models.models import Loan, Installment, Customer, Company, Payment, Employee
from app.routes.installments import _assert_customer_scoped
from app.schemas.installments import InstallmentOut
from app.schemas.loans import (
    CancelRequest, LoanListItem, LoansOut, LoansCreate, LoansSummaryResponse, LoansUpdate,
    RefinanceRequest, LoanPaymentRequest
)
from app.utils.auth import ensure_admin, get_current_user
from app.utils.ledger import recompute_ledger_for_loan
from app.utils.license import ensure_company_active
from app.utils.status import normalize_loan_status_filter, update_status_if_fully_paid
from pydantic import BaseModel

# 🔹 NUEVO: Enums canónicos y normalizadores
from app.constants import InstallmentStatus, LoanStatus
from app.utils.normalize import norm_loan_status
from app.utils.time_windows import parse_iso_aware_utc, local_dates_to_utc_window, AR_TZ

from sqlalchemy.orm import Session, joinedload
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from io import BytesIO
from zoneinfo import ZoneInfo
from app.services.coupons_v5 import CouponV5Data, build_coupons_v5_pdf

from typing import Optional
from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import Query, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from sqlalchemy.sql import literal



router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],  # 👈 exige Bearer válido en todo el router
)

# ---------- helpers fecha ----------
from datetime import date as date_cls, datetime, timezone


def loan_is_effective_for_loans(Loan):
    """
    Clausula 'préstamo efectivo' que NO referencia Installment.
    Evita JOINs que multiplican filas cuando la entidad base es Loan.
    Ajustá los nombres de campos a tu modelo real.
    """
    # Si tenés flags booleanos:
    clauses = [ (getattr(Loan, "is_canceled", False) == False),
                (getattr(Loan, "is_refinanced", False) == False) ]

    # Si además usás un status string:
    if hasattr(Loan, "status"):
        clauses.append( ~getattr(Loan, "status").in_(["canceled", "cancelled", "refinanced"]) )

    return and_(*clauses)


def _parse_iso(dt: str | None) -> datetime | None:
    """
    Acepta:
      - 'YYYY-MM-DD'
      - 'YYYY-MM-DDTHH:MM[:SS[.ffffff]]'
      - con 'Z' (UTC) o +00:00
    Devuelve datetime naive (UTC) para comparar en DB sin tz-aware.
    """
    if not dt:
        return None
    s = dt.strip()
    try:
        # Aceptar 'Z' como UTC
        s_norm = s.replace('Z', '+00:00')
        dtx = datetime.fromisoformat(s_norm)
        # Normalizar a naive UTC
        if dtx.tzinfo is not None:
            dtx = dtx.astimezone(timezone.utc).replace(tzinfo=None)
        return dtx
    except Exception:
        # Fallback: solo fecha 'YYYY-MM-DD'
        try:
            d = date_cls.fromisoformat(s.split('T')[0])
            return datetime(d.year, d.month, d.day)
        except Exception:
            return None

def _normalize_range(date_from: str | None, date_to: str | None):
    df = _parse_iso(date_from)
    dt = _parse_iso(date_to)

    if date_from and not df:
        raise HTTPException(
            status_code=422,
            detail=f"Formato de date_from inválido: {date_from}. Use 'YYYY-MM-DD' o ISO 8601."
        )
    if date_to and not dt:
        raise HTTPException(
            status_code=422,
            detail=f"Formato de date_to inválido: {date_to}. Use 'YYYY-MM-DD' o ISO 8601."
        )

    if df:
        df = df.replace(hour=0, minute=0, second=0, microsecond=0)
    if dt:
        dt = dt.replace(hour=23, minute=59, second=59, microsecond=999999)
    return df, dt
# -----------------------------------

def _404():
    raise HTTPException(status_code=404, detail="Recurso no encontrado")

def _assert_customer_same_company(customer_id: int, db: Session, current: Employee) -> Customer:
    cust = db.query(Customer).filter(Customer.id == customer_id).first()
    if not cust or cust.company_id != current.company_id:
        _404()
    return cust

def _assert_loan_same_company(loan_id: int, db: Session, current: Employee) -> Loan:
    # Si Loan tiene company_id, usamos eso (rápido); si no, validamos por join a Customer
    q = db.query(Loan).filter(Loan.id == loan_id)
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = q.join(Customer, Customer.id == Loan.customer_id).filter(Customer.company_id == current.company_id)
    loan = q.first()
    if not loan:
        _404()
    return loan

def _coupon_data_for_loan(loan: Loan, db: Session, tz: str) -> CouponV5Data:
    tzinfo = ZoneInfo(tz)
    today = datetime.now(tzinfo).date()

    # 1) primera cuota no pagada (más vieja)
    inst = (
    db.query(Installment)
    .filter(Installment.loan_id == loan.id)
    .filter(
        func.coalesce(Installment.amount, 0) >
        func.coalesce(Installment.paid_amount, 0)
    )
    .filter(
        Installment.status.notin_([
            InstallmentStatus.CANCELED.value,
            InstallmentStatus.REFINANCED.value,
        ])
    )
    .order_by(
        Installment.due_date.asc(),
        Installment.number.asc(),
        Installment.id.asc(),
    )
    .first()
    )

    if not inst:
        raise HTTPException(status_code=409, detail=f"El préstamo #{loan.id} no tiene cuotas pendientes (ya estaría pagado).")

    due = inst.due_date.astimezone(tzinfo).date() if getattr(inst.due_date, "astimezone", None) else inst.due_date.date()
    is_overdue = due < today
    days_overdue = max(0, (today - due).days) if is_overdue else 0

    # 2) total pagado (sin anulados)
    total_paid = (
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.loan_id == loan.id)
        .filter(Payment.is_voided == False)
        .scalar()
    ) or 0.0

    remaining = max(0.0, float(loan.total_due or 0.0))

    # 3) atraso: cuotas vencidas impagas + monto vencido (saldo de cuota)
    overdue_q = (
        db.query(Installment)
        .filter(Installment.loan_id == loan.id)
        .filter(Installment.is_paid == False)
        .filter(Installment.due_date < datetime.now(tzinfo))
        .all()
    )
    overdue_count = len(overdue_q)
    overdue_amount = 0.0
    for it in overdue_q:
        amt = float(it.amount or 0.0)
        paid_amt = float(it.paid_amount or 0.0)
        overdue_amount += max(0.0, amt - paid_amt)

    company_name = loan.company.name if loan.company else "Empresa"
    company_cuit = None  # hoy Company no tiene CUIT en tu modelo

    customer_name = loan.customer.full_name if loan.customer else "Cliente"
    customer_address = getattr(loan.customer, "address", None) if loan.customer else None
    customer_province = getattr(loan.customer, "province", None) if loan.customer else None

    collector_name = loan.employee.name if loan.employee else None
    description = getattr(loan, "description", None)

    installment_total = float(getattr(inst, "amount", 0.0) or 0.0)
    paid_amount = float(getattr(inst, "paid_amount", 0.0) or 0.0)
    installment_balance = max(0.0, installment_total - paid_amount)


    return CouponV5Data(
        company_name=company_name,
        company_cuit=company_cuit,
        customer_name=customer_name,
        customer_address=customer_address,
        customer_province=customer_province,
        collector_name=collector_name,
        description=description,
        loan_id=loan.id,
        installment_number=int(inst.number),
        installments_count=int(loan.installments_count),
        due_date=due,
        installment_amount=installment_total,      # ✅ monto original de la cuota
        installment_balance=installment_balance, 
        total_paid=float(total_paid or 0.0),
        remaining=float(remaining),
        overdue_count=int(overdue_count),
        overdue_amount=float(overdue_amount),
        is_overdue=bool(is_overdue),
        days_overdue=int(days_overdue),
    )

def get_payment_stats_for_loan(db: Session, loan_id: int):
    row = (
        db.query(
            func.count(Payment.id).label("payments_count"),
            func.coalesce(func.sum(Payment.amount), 0).label("total_paid"),
        )
        .filter(Payment.loan_id == loan_id)
        .filter(func.coalesce(Payment.is_voided, False) == False)  # noqa: E712
        .one()
    )
    payments_count = int(row.payments_count or 0)
    total_paid = float(row.total_paid or 0)
    return payments_count, total_paid


def _has_non_voided_payments(db: Session, loan: Loan) -> tuple[bool, int, float]:
    payments_count = (
        db.query(func.count(Payment.id))
        .filter(
            Payment.loan_id == loan.id,
            Payment.is_voided == False,  # noqa: E712
        )
        .scalar()
        or 0
    )

    total_paid = (
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(
            Payment.loan_id == loan.id,
            Payment.is_voided == False,  # noqa: E712
        )
        .scalar()
        or 0.0
    )

    has_payments = payments_count > 0 or float(total_paid) > 0.0
    return has_payments, int(payments_count), float(total_paid)


def _validate_collection_day(v: int | None):
    if v is None:
        return
    if not (1 <= int(v) <= 7):
        raise HTTPException(status_code=422, detail="collection_day debe ser 1..7 (Lun..Dom)")


def _assert_customer_same_company_put(db: Session, customer_id: int, company_id: int):
    exists = (
        db.query(Customer.id)
        .filter(Customer.id == customer_id, Customer.company_id == company_id)
        .first()
    )
    if not exists:
        raise HTTPException(status_code=422, detail="customer_id inválido para esta empresa")


def _assert_employee_same_company(db: Session, employee_id: int, company_id: int):
    exists = (
        db.query(Employee.id)
        .filter(Employee.id == employee_id, Employee.company_id == company_id)
        .first()
    )
    if not exists:
        raise HTTPException(status_code=422, detail="employee_id inválido para esta empresa")


def _rebuild_installments_for_loan(db: Session, loan: Loan):
    """
    Reconstruye cuotas SOLO cuando NO hay pagos (y por lo tanto todas las cuotas deben resetearse).
    due_date es DateTime(timezone=True) en tu modelo.
    """
    if not loan.installments_count or loan.installments_count <= 0:
        raise HTTPException(status_code=422, detail="installments_count debe ser > 0")
    if not loan.installment_interval_days or loan.installment_interval_days <= 0:
        raise HTTPException(status_code=422, detail="installment_interval_days debe ser > 0")
    if not loan.installment_amount or loan.installment_amount <= 0:
        raise HTTPException(status_code=422, detail="installment_amount debe ser > 0")

    start_dt = loan.start_date
    if not start_dt:
        start_dt = datetime.now(timezone.utc)
        loan.start_date = start_dt
    if start_dt.tzinfo is None:
        # blindaje
        start_dt = start_dt.replace(tzinfo=timezone.utc)
        loan.start_date = start_dt

    # borrar cuotas existentes
    db.query(Installment).filter(Installment.loan_id == loan.id).delete(synchronize_session=False)
    db.flush()

    interval = int(loan.installment_interval_days)

    new_rows: list[Installment] = []
    for n in range(1, int(loan.installments_count) + 1):
        due_dt = start_dt + timedelta(days=interval * (n - 1))
        inst = Installment(
            loan_id=loan.id,
            purchase_id=None,
            number=n,
            due_date=due_dt,
            amount=float(loan.installment_amount),
            paid_amount=0.0,
            is_paid=False,
            status=InstallmentStatus.PENDING.value,
            is_overdue=False,
        )
        new_rows.append(inst)

    db.add_all(new_rows)
    db.flush()


# ============== SUMMARY ==============
@router.get("/summary", response_model=LoansSummaryResponse)
def loans_summary(
    employee_id: int | None = Query(None),
    date_from: str | None = Query(None),
    date_to: str | None = Query(None),
    province: str | None = Query(None),
    by_day: bool = Query(False),
    tz: str | None = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: str | None) -> bool:
        return bool(s) and len(s) == 10 and s[4] == "-" and s[7] == "-"

    start_utc = end_utc_excl = None
    if _looks_like_date(date_from) and _looks_like_date(date_to):
        dfrom = date.fromisoformat(date_from) if date_from else None
        dto   = date.fromisoformat(date_to)   if date_to   else None
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(date_from)
        end_utc   = parse_iso_aware_utc(date_to)
        end_utc_excl = end_utc

        q = db.query(Loan)

    # 👇 Regla de visibilidad por rol:
    # - collector: siempre ve SOLO sus préstamos (employee_id = current.id)
    # - admin/manager: puede ver todos o filtrar por employee_id explícito
    effective_employee_id: int | None = employee_id
    if current.role == "collector":
        # Ignoramos cualquier employee_id que venga por query
        effective_employee_id = current.id

    # Necesitamos join con Customer SOLO si filtramos por provincia
    needs_customer = (province is not None) or (not hasattr(Loan, "company_id"))

    if hasattr(Loan, "company_id") and not needs_customer:
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = (
            q.join(Customer, Loan.customer_id == Customer.id)
             .filter(Customer.company_id == current.company_id)
        )
        if province is not None:
            q = q.filter(Customer.province == province)

    # Filtro por cobrador (a nivel Loan)
    if effective_employee_id is not None:
        q = q.filter(Loan.employee_id == effective_employee_id)


    # ✅ filtro por préstamos efectivos sin tocar Installment
    q = q.filter(loan_is_effective_for_loans(Loan))

    if start_utc is not None:
        q = q.filter(Loan.start_date >= start_utc)
    if end_utc_excl is not None:
        q = q.filter(Loan.start_date <  end_utc_excl)

    # ✅ Subquery DISTINCT para evitar multiplicación de filas en agregados
    subq = q.with_entities(Loan.id.label("id"),
                           func.coalesce(Loan.amount, 0.0).label("amount"),
                           Loan.start_date.label("start_date"))\
            .distinct(Loan.id)\
            .subquery()

    # KPIs
    count = db.query(func.count(subq.c.id)).scalar() or 0
    amount = db.query(func.coalesce(func.sum(subq.c.amount), 0.0)).scalar() or 0.0

    result = {
        "count": int(count),
        "amount": float(amount),
        "by_day": [],
    }

    if by_day:
        tzname = tz or "America/Argentina/Buenos_Aires"
        # agrupamos sobre el subquery para no duplicar
        day_local = func.date(func.timezone(tzname, subq.c.start_date))
        rows = (
            db.query(
                day_local.label("d"),
                func.count(subq.c.id).label("cnt"),
                func.coalesce(func.sum(subq.c.amount), 0.0).label("amt"),
            )
            .group_by(day_local)
            .order_by(day_local)
            .select_from(subq)
            .all()
        )
        result["by_day"] = [
            {"date": r.d, "count": int(r.cnt or 0), "amount": float(r.amt or 0.0)}
            for r in rows
        ]

    return LoansSummaryResponse(**result)



@router.get("/all", response_model=List[LoanListItem])
def list_loans_all(
    employee_id: Optional[int] = Query(None),

    # Front puede mandar cualquiera de estos:
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    created_from: Optional[str] = Query(None),  # alias
    created_to: Optional[str] = Query(None),    # alias

    province: Optional[str] = Query(None),
    tz: Optional[str] = Query(None),

    status: Optional[str] = Query(None),  # ✅ NEW
    q: Optional[str] = Query(None),       # ✅ NEW (personalizado)

    # ✅ Paginado SIEMPRE
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),

    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    # compat: el admin-portal usa created_from/created_to
    if not date_from and created_from:
        date_from = created_from
    if not date_to and created_to:
        date_to = created_to

    def _looks_like_date(s: Optional[str]) -> bool:
        return bool(s) and len(s) == 10 and s[4] == "-" and s[7] == "-"

    # ---- Rango local → ventana UTC (robusto: from/to parciales) ----
    start_utc = None
    end_utc_excl = None

    dfrom = date.fromisoformat(date_from) if _looks_like_date(date_from) else None
    dto = date.fromisoformat(date_to) if _looks_like_date(date_to) else None

    if dfrom or dto:
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
        elif dfrom and not dto:
            # desde ese día (inclusive) en adelante
            start_utc, _ = local_dates_to_utc_window(dfrom, dfrom, zone)
            end_utc_excl = None
        elif dto and not dfrom:
            # hasta ese día (inclusive)
            _, end_utc_excl = local_dates_to_utc_window(dto, dto, zone)
            start_utc = None
    else:
        # fallback: ISO aware (UTC)
        start_utc = parse_iso_aware_utc(date_from)
        end_utc_excl = parse_iso_aware_utc(date_to)

    # Nombre cliente
    cust_name = func.trim(
        func.concat(
            func.coalesce(Customer.first_name, ""),
            literal(" "),
            func.coalesce(Customer.last_name, ""),
        )
    ).label("customer_name")

    # ============================================================
    # Subquery: SALDO RESTANTE por préstamo
    # remaining_due = SUM(max(amount - paid_amount, 0))
    # ============================================================
    remaining_sq = (
        db.query(
            Installment.loan_id.label("loan_id"),
            func.coalesce(
                func.sum(
                    case(
                        (
                            (func.coalesce(Installment.amount, 0.0) -
                             func.coalesce(Installment.paid_amount, 0.0)) > 0,
                            (func.coalesce(Installment.amount, 0.0) -
                             func.coalesce(Installment.paid_amount, 0.0)),
                        ),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("remaining_due"),
        )
        .group_by(Installment.loan_id)
        .subquery()
    )

    # ============================================================
    # 1) SUBQUERY de IDs
    # ============================================================
    effective_employee_id: Optional[int] = employee_id
    if (current.role or "").lower() == "collector":
        effective_employee_id = current.id

    # ✅ necesitamos join con Customer si filtramos por provincia o si usamos q (porque q busca nombre/provincia)
    needs_customer = (province is not None) or (q is not None and str(q).strip() != "")

    base_ids = db.query(Loan.id)

    # Siempre por empresa
    base_ids = base_ids.filter(Loan.company_id == current.company_id)

    # Join con Customer solo si hace falta (provincia o q)
    if needs_customer:
        base_ids = base_ids.join(Customer, Loan.customer_id == Customer.id)

        if province is not None:
            base_ids = base_ids.filter(Customer.province == province)

    # Filtro por cobrador a nivel Loan
    if effective_employee_id is not None:
        base_ids = base_ids.filter(Loan.employee_id == effective_employee_id)

    # ✅ Filtro por status (acepta ES/legacy o EN canónico)
    canonical_status = normalize_loan_status_filter(status)
    if canonical_status:
        base_ids = base_ids.filter(Loan.status == canonical_status)

    # ✅ Filtro personalizado q (nombre cliente / provincia / id préstamo)
    q_str = (q or "").strip()
    if q_str:
        like = f"%{q_str}%"
        conditions = []

        # si es número: permitir buscar por ID exacto
        if q_str.isdigit():
            conditions.append(Loan.id == int(q_str))

        # si tenemos Customer join (lo tenemos si needs_customer=True)
        if needs_customer:
            conditions.append(Customer.first_name.ilike(like))
            conditions.append(Customer.last_name.ilike(like))
            conditions.append(Customer.province.ilike(like))

        # si no hay conditions por alguna razón, no aplicamos nada
        if conditions:
            base_ids = base_ids.filter(or_(*conditions))

    # Rango por start_date (UTC)
    if start_utc is not None:
        base_ids = base_ids.filter(Loan.start_date >= start_utc)
    if end_utc_excl is not None:
        base_ids = base_ids.filter(Loan.start_date < end_utc_excl)

    ids_subq = base_ids.distinct().subquery()

    # ============================================================
    # 2) QUERY FINAL
    # ============================================================
    q2 = (
        db.query(
            Loan.id.label("id"),
            func.coalesce(Loan.amount, 0.0).label("amount"),
            Loan.start_date.label("start_date"),
            cust_name,
            Customer.province.label("customer_province"),

            Loan.employee_id.label("collector_id"),
            Employee.name.label("collector_name"),

            # compatibilidad
            Employee.name.label("employee_name"),

            func.coalesce(Loan.total_due, 0.0).label("total_due"),
            func.coalesce(remaining_sq.c.remaining_due, 0.0).label("remaining_due"),
            Loan.status.label("status"),
        )
        .join(ids_subq, ids_subq.c.id == Loan.id)
        .join(Customer, Loan.customer_id == Customer.id)
        .outerjoin(Employee, Employee.id == Loan.employee_id)
        .outerjoin(remaining_sq, remaining_sq.c.loan_id == Loan.id)
    )

    rows = (
        q2.order_by(Loan.start_date.desc(), Loan.id.desc())
          .offset(offset)
          .limit(limit)
          .all()
    )

    return [
        LoanListItem(
            id=r.id,
            amount=float(r.amount or 0.0),
            start_date=r.start_date,
            customer_name=(r.customer_name or "-"),
            customer_province=r.customer_province,

            collector_id=r.collector_id,
            collector_name=r.collector_name,
            employee_name=r.employee_name,

            total_due=float(r.total_due or 0.0),
            remaining_due=float(r.remaining_due or 0.0),
            status=r.status,
        )
        for r in rows
    ]

@router.get("/", response_model=List[LoanListItem])
def list_loans(
    employee_id: Optional[int] = Query(None),
    customer_id: Optional[int] = Query(None),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    province: Optional[str] = Query(None),
    tz: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: Optional[str]) -> bool:
        return bool(s) and len(s) == 10 and s[4] == "-" and s[7] == "-"

    # ---- Rango local → ventana UTC ----
    start_utc = end_utc_excl = None
    if _looks_like_date(date_from) and _looks_like_date(date_to):
        dfrom = date.fromisoformat(date_from) if date_from else None
        dto   = date.fromisoformat(date_to)   if date_to   else None
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(date_from)
        end_utc   = parse_iso_aware_utc(date_to)
        end_utc_excl = end_utc

    # Nombre cliente
    cust_name = func.trim(
        func.concat(
            func.coalesce(Customer.first_name, ""),
            literal(" "),
            func.coalesce(Customer.last_name, "")
        )
    ).label("customer_name")

    # ============================================================
    # Subquery: SALDO RESTANTE por préstamo
    # remaining_due = SUM(max(amount - paid_amount, 0))
    # ============================================================
    remaining_sq = (
        db.query(
            Installment.loan_id.label("loan_id"),
            func.coalesce(
                func.sum(
                    case(
                        (
                            (func.coalesce(Installment.amount, 0.0) -
                             func.coalesce(Installment.paid_amount, 0.0)) > 0,
                            (func.coalesce(Installment.amount, 0.0) -
                             func.coalesce(Installment.paid_amount, 0.0)),
                        ),
                        else_=0.0,
                    )
                ),
                0.0,
            ).label("remaining_due"),
        )
        .group_by(Installment.loan_id)
        .subquery()
    )

    # ============================================================
    # 1) SUBQUERY de IDs (NO TOCADO)
    # ============================================================
    effective_employee_id: Optional[int] = employee_id
    if current.role == "collector":
        effective_employee_id = current.id

    needs_customer = True if (province is not None or customer_id is not None) else (not hasattr(Loan, "company_id"))


    base_ids = db.query(Loan.id)

    # Siempre filtramos por empresa usando Loan.company_id (ya existe)
    base_ids = base_ids.filter(Loan.company_id == current.company_id)

    if customer_id is not None:
        base_ids = base_ids.filter(Loan.customer_id == customer_id)
    

    # Join con Customer solo si hace falta por provincia
    if needs_customer:
        base_ids = base_ids.join(Customer, Loan.customer_id == Customer.id)
        if province is not None:
            base_ids = base_ids.filter(Customer.province == province)

    # Filtro por cobrador a nivel Loan
    if effective_employee_id is not None:
        base_ids = base_ids.filter(Loan.employee_id == effective_employee_id)

    # Excluir loans cancel/refinanced (usa sólo columnas de Loan)
    base_ids = base_ids.filter(loan_is_effective_for_loans(Loan))

    # Rango por start_date
    if start_utc is not None:
        base_ids = base_ids.filter(Loan.start_date >= start_utc)
    if end_utc_excl is not None:
        base_ids = base_ids.filter(Loan.start_date < end_utc_excl)

    # DISTINCT de IDs SIN ORDER BY
    ids_subq = base_ids.distinct().subquery()

    # ============================================================
    # 2) QUERY FINAL (AMPLIADO)
    #    Cobrador igual que /printables: collector_id + collector_name
    # ============================================================
    q2 = (
        db.query(
            Loan.id.label("id"),
            func.coalesce(Loan.amount, 0.0).label("amount"),
            Loan.start_date.label("start_date"),
            cust_name,
            Customer.province.label("customer_province"),

            # cobrador (misma lógica que printables)
            Loan.employee_id.label("collector_id"),
            Employee.name.label("collector_name"),

            # compatibilidad
            Employee.name.label("employee_name"),

            # extra
            func.coalesce(Loan.total_due, 0.0).label("total_due"),
            func.coalesce(remaining_sq.c.remaining_due, 0.0).label("remaining_due"),
            Loan.status.label("status"),
        )
        .join(ids_subq, ids_subq.c.id == Loan.id)
        .join(Customer, Loan.customer_id == Customer.id)
        .outerjoin(Employee, Employee.id == Loan.employee_id)
        .outerjoin(remaining_sq, remaining_sq.c.loan_id == Loan.id)
    )

    rows = (
        q2.order_by(Loan.start_date.desc(), Loan.id.desc())
           .offset(offset)
           .limit(limit)
           .all()
    )

    return [
        LoanListItem(
            id=r.id,
            amount=float(r.amount or 0.0),
            start_date=r.start_date,
            customer_name=(r.customer_name or "-"),
            customer_province=r.customer_province,

            collector_id=r.collector_id,
            collector_name=r.collector_name,
            employee_name=r.employee_name,

            total_due=float(r.total_due or 0.0),
            remaining_due=float(r.remaining_due or 0.0),
            status=r.status,
        )
        for r in rows
    ]








# ============== CREATE ==============
@router.post("/createLoan/", response_model=LoansOut, status_code=status.HTTP_201_CREATED)
def create_loan(
    loan: LoansCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
    ):
    # Validar cliente y empresa
    customer = _assert_customer_same_company(loan.customer_id, db, current)

    zone = AR_TZ  # p.ej. ZoneInfo("America/Argentina/Buenos_Aires")

    # === 1) Definir start_date en HORARIO LOCAL ===
    if loan.start_date:
        sd = loan.start_date

        # Si viene sin tzinfo, interpretarla como hora LOCAL, no como UTC
        if sd.tzinfo is None:
            sd = sd.replace(tzinfo=zone)

        # Trabajamos en local
        start_local = sd.astimezone(zone)
    else:
        # Si no viene, usar ahora local
        start_local = datetime.now(zone)

    # Guardar start_date en UTC en la Loan
    start_date_utc = start_local.astimezone(timezone.utc)

    # === 2) Determinar el cobrador (employee_id del préstamo) ===
    # Regla:
    # - Si es collector: siempre él mismo.
    # - Si es admin/manager: puede elegir employee_id en el payload.
    target_employee_id: int

    role = (current.role or "").lower()

    if role == "collector":
        # El cobrador siempre es el usuario logueado
        target_employee_id = current.id
    else:
        # Admin/manager: puede elegir un cobrador
        # (loan.employee_id viene del frontend; es opcional)
        requested_emp_id = getattr(loan, "employee_id", None)

        if requested_emp_id is not None:
            # Validar que el empleado exista y sea de la misma empresa
            target_emp = (
                db.query(Employee)
                .filter(
                    Employee.id == requested_emp_id,
                    Employee.company_id == current.company_id,
                )
                .first()
            )
            if not target_emp:
                raise HTTPException(
                    status_code=400,
                    detail="Empleado inválido o de otra empresa para este préstamo",
                )
            target_employee_id = target_emp.id
        else:
            # Si el admin no envía employee_id, el préstamo queda a su nombre
            target_employee_id = current.id

    # === 3) Crear el Loan ===
    new_loan = Loan(
        # Excluimos company_id (si lo mandan) y employee_id (lo definimos nosotros)
        **loan.model_dump(exclude={"installments", "start_date", "company_id", "employee_id"}),
        start_date=start_date_utc,
        total_due=loan.amount,
        company_id=current.company_id,
        employee_id=target_employee_id,  # 👈 dueño del crédito
    )

    # installment_amount
    installment_amount = round(loan.amount / loan.installments_count, 2)
    if hasattr(Loan, "installment_amount"):
        new_loan.installment_amount = installment_amount

    db.add(new_loan)
    db.commit()
    db.refresh(new_loan)

    # === 4) Crear cuotas en base a start_local ===
    interval_days = loan.installment_interval_days
    if interval_days is None or interval_days < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="installment_interval_days es requerido y debe ser >= 1.",
        )
    
    for i in range(loan.installments_count):
        due_local = start_local + timedelta(days=interval_days * (i + 1))

        # due_date = medianoche LOCAL → UTC
        local_midnight = due_local.replace(hour=0, minute=0, second=0, microsecond=0)
        due_date_utc = local_midnight.astimezone(timezone.utc)

        # status inicial según día local
        today_local = datetime.now(zone).date()
        is_overdue = (local_midnight.date() < today_local)
        init_status = (
            InstallmentStatus.OVERDUE.value
            if is_overdue
            else InstallmentStatus.PENDING.value
        )

        installment = Installment(
            loan_id=new_loan.id,
            amount=installment_amount,
            due_date=due_date_utc,  # UTC
            is_paid=False,
            status=init_status,
            number=i + 1,
            paid_amount=0.0,
            is_overdue=is_overdue,
        )
        db.add(installment)

    db.commit()
    return new_loan

# Loan, Installment, Customer, Payment, Employee ya están importados en tu archivo
# get_db, get_current_user, AR_TZ, loan_is_effective_for_loans ya existen

@router.get("/printables")
def list_loans_printables(
    q: Optional[str] = Query(None, description="Busca por cliente/telefono/dni"),
    collector_id: Optional[int] = Query(None),
    province: Optional[str] = Query(None),
    tz: Optional[str] = Query("America/Argentina/Tucuman"),
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz or "America/Argentina/Tucuman")
    now_local = datetime.now(zone)
    today_local = now_local.date()

    # Regla por rol: collector ve solo sus préstamos
    effective_collector_id = collector_id
    if (current.role or "").lower() == "collector":
        effective_collector_id = current.id

    # -----------------------------
    # 1) Subquery: primera cuota impaga por préstamo (más vieja)
    # -----------------------------
    rn = func.row_number().over(
        partition_by=Installment.loan_id,
        order_by=(Installment.due_date.asc(), Installment.number.asc(), Installment.id.asc()),
    ).label("rn")

    first_unpaid_subq = (
    db.query(
        Installment.loan_id.label("loan_id"),
        Installment.id.label("installment_id"),
        Installment.number.label("installment_number"),
        Installment.due_date.label("due_date"),
        Installment.amount.label("installment_amount"),
        Installment.paid_amount.label("installment_paid_amount"),
        rn,
    )
    .filter(Installment.loan_id.isnot(None))
    .filter(Installment.is_paid.is_(False))
    .subquery()
)


    first_unpaid = (
        db.query(first_unpaid_subq)
        .filter(first_unpaid_subq.c.rn == 1)
        .subquery()
    )

    # -----------------------------
    # 2) Subqueries (pagado / atraso)
    # -----------------------------
    total_paid_subq = (
        db.query(
            Payment.loan_id.label("loan_id"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("total_paid"),
        )
        .filter(Payment.is_voided.is_(False))
        .group_by(Payment.loan_id)
        .subquery()
    )

    overdue_amount_subq = (
        db.query(
            Installment.loan_id.label("loan_id"),
            func.coalesce(
                func.sum(
                    func.greatest(
                        func.coalesce(Installment.amount, 0.0) - func.coalesce(Installment.paid_amount, 0.0),
                        0.0,
                    )
                ),
                0.0,
            ).label("overdue_amount"),
            func.coalesce(func.count(Installment.id), 0).label("overdue_count"),
        )
        .filter(Installment.is_paid.is_(False))
        .filter(Installment.due_date < datetime.now(tz=ZoneInfo("UTC")))
        .group_by(Installment.loan_id)
        .subquery()
    )

    # -----------------------------
    # 3) Query base
    # -----------------------------
    cust_name = func.trim(
        func.concat(
            func.coalesce(Customer.first_name, ""),
            literal(" "),
            func.coalesce(Customer.last_name, ""),
        )
    ).label("customer_name")

    base = (
        db.query(
            Loan.id.label("loan_id"),
            cust_name,
            Customer.address.label("customer_address"),
            Customer.province.label("customer_province"),
            Customer.phone.label("customer_phone"),
            Customer.dni.label("customer_dni"),
            Loan.employee_id.label("collector_id"),
            Employee.name.label("collector_name"),
            Loan.description.label("description"),

            first_unpaid.c.installment_id,
            first_unpaid.c.installment_number,
            Loan.installments_count.label("installments_count"),
            first_unpaid.c.due_date,
            first_unpaid.c.installment_amount,
            first_unpaid.c.installment_paid_amount,
            func.greatest(
            func.coalesce(first_unpaid.c.installment_amount, 0.0) - func.coalesce(first_unpaid.c.installment_paid_amount, 0.0),
            0.0).label("installment_balance"),

            func.coalesce(total_paid_subq.c.total_paid, 0.0).label("total_paid"),

            # ✅ remaining = Loan.total_due (ya es saldo)
            func.coalesce(Loan.total_due, 0.0).label("remaining"),

            func.coalesce(overdue_amount_subq.c.overdue_count, 0).label("overdue_count"),
            func.coalesce(overdue_amount_subq.c.overdue_amount, 0.0).label("overdue_amount"),
            func.coalesce(Loan.amount, 0.0).label("total_due"),
        )
        .join(Customer, Customer.id == Loan.customer_id)
        .outerjoin(Employee, Employee.id == Loan.employee_id)
        .join(first_unpaid, first_unpaid.c.loan_id == Loan.id)  # solo loans con cuota impaga
        .outerjoin(total_paid_subq, total_paid_subq.c.loan_id == Loan.id)
        .outerjoin(overdue_amount_subq, overdue_amount_subq.c.loan_id == Loan.id)
        .filter(Loan.company_id == current.company_id)
        .filter(loan_is_effective_for_loans(Loan))
    )

    if province:
        base = base.filter(Customer.province == province)

    if effective_collector_id is not None:
        base = base.filter(Loan.employee_id == effective_collector_id)

    if q and q.strip():
        s = f"%{q.strip()}%"
        base = base.filter(
            or_(
                Customer.first_name.ilike(s),
                Customer.last_name.ilike(s),
                cust_name.ilike(s),
                Customer.phone.ilike(s),
                Customer.dni.ilike(s),
            )
        )

    total = base.with_entities(func.count()).scalar() or 0

    rows = (
        base.order_by(
            Customer.province.asc().nulls_last(),
            Employee.name.asc().nulls_last(),
            Loan.id.desc(),
        )
        .offset(offset)
        .limit(limit)
        .all()
    )

    data = []
    for r in rows:
        dd = r.due_date
        due_local_date = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd.date()
        is_overdue = due_local_date < today_local
        days_overdue = (today_local - due_local_date).days if is_overdue else 0

        data.append({
            "loan_id": int(r.loan_id),

            "customer_name": r.customer_name or "-",
            "customer_address": r.customer_address,
            "customer_province": r.customer_province,
            "customer_phone": r.customer_phone,
            "customer_dni": r.customer_dni,

            "collector_id": r.collector_id,
            "collector_name": r.collector_name,

            "description": r.description,

            "installment_id": int(r.installment_id),
            "installment_number": int(r.installment_number),
            "installments_count": int(r.installments_count or 0),
            "due_date": due_local_date.isoformat(),

            "is_overdue": bool(is_overdue),
            "days_overdue": int(days_overdue),

            "total_paid": float(r.total_paid or 0.0),
            "remaining": float(r.remaining or 0.0),
            "overdue_count": int(r.overdue_count or 0),
            "overdue_amount": float(r.overdue_amount or 0.0),
            "total_due": float(r.total_due or 0.0),
            "installment_amount": float(r.installment_amount or 0.0),          # total cuota
            "installment_paid_amount": float(r.installment_paid_amount or 0.0),# pagado cuota
            "installment_balance": float(r.installment_balance or 0.0),        # saldo cuota (lo que se imprime)
        })

    return {"data": data, "total": int(total)}


@router.get("/customer/{customer_id}", response_model=list[LoansOut])
def get_loans_by_customer(
    customer_id: int,
    tz: Optional[str] = Query(None),
    include_installments: bool = Query(False),  # 👈 NUEVO (opt-in)
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_customer_same_company(customer_id, db, current)

    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()

    # 1) Query base loans
    q = db.query(Loan).filter(
        Loan.customer_id == customer_id,
        Loan.company_id == current.company_id,
    )

    if current.role == "collector":
        q = q.filter(Loan.employee_id == current.id)

    # Si vas a incluir installments, precargalos para no hacer N+1
    if include_installments:
        q = q.options(joinedload(Loan.installments), joinedload(Loan.employee))
    else:
        q = q.options(joinedload(Loan.employee))

    loans = q.all()
    if not loans:
        return []

    loan_ids = [l.id for l in loans]

    # 2) Agregados de pagos (ajustá filtros según tu modelo: voided, status, etc.)
    payments_agg = (
        db.query(
            Payment.loan_id.label("loan_id"),
            func.count(Payment.id).label("payments_count"),
            func.coalesce(func.sum(Payment.amount), 0).label("total_paid"),
        )
        .filter(
            Payment.loan_id.in_(loan_ids),
            # Si tenés "is_voided" o "status" en Payment, filtralo acá
            # Payment.is_voided == False,
        )
        .group_by(Payment.loan_id)
        .all()
    )


    agg_map = {
        row.loan_id: {
            "payments_count": int(row.payments_count or 0),
            "total_paid": float(row.total_paid or 0),
        }
        for row in payments_agg
    }

    # 3) Armar response
    out: list[LoansOut] = []
    for loan in loans:
        agg = agg_map.get(loan.id, {"payments_count": 0, "total_paid": 0.0})
        total_paid = agg["total_paid"]
        remaining = float((loan.total_due or 0) - total_paid)

        installments_out: list[InstallmentOut] = []
        if include_installments:
            for inst in loan.installments:
                dd = inst.due_date
                due_local_date = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd
                is_overdue = (not inst.is_paid) and (due_local_date and due_local_date < today_local)

                installments_out.append(InstallmentOut(
                    id=inst.id,
                    amount=inst.amount,
                    due_date=inst.due_date,
                    status=inst.status,
                    is_paid=inst.is_paid,
                    loan_id=loan.id,
                    is_overdue=is_overdue,
                    number=inst.number,
                    paid_amount=inst.paid_amount,
                ))

        out.append(LoansOut(
            id=loan.id,
            customer_id=loan.customer_id,
            amount=loan.amount,
            total_due=loan.total_due,
            installments_count=loan.installments_count,
            installment_amount=getattr(loan, "installment_amount", None),
            installment_interval_days=getattr(loan, "installment_interval_days", None),
            start_date=loan.start_date,
            status=loan.status,
            company_id=getattr(loan, "company_id", None),

            # 🔹 nuevos agregados
            payments_count=agg["payments_count"],
            total_paid=total_paid,
            remaining=remaining,

            installments=installments_out,
            employee_name=loan.employee.name if loan.employee else None,
        ))

    return out

@router.get("/by-employee", response_model=List[LoansOut])
def get_loans_by_employee(
    employee_id: int = Query(...),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    tz: Optional[str] = Query(None),                      # 👈 NUEVO
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: str | None) -> bool:
        return bool(s) and len(s) == 10 and s[4] == "-" and s[7] == "-"

    start_utc = end_utc_excl = None
    if _looks_like_date(date_from) and _looks_like_date(date_to):
        dfrom = date.fromisoformat(date_from) if date_from else None
        dto   = date.fromisoformat(date_to)   if date_to   else None
        if dfrom and dto:
            start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
    else:
        start_utc = parse_iso_aware_utc(date_from)
        end_utc   = parse_iso_aware_utc(date_to)
        end_utc_excl = end_utc

    q = db.query(Loan).filter(Loan.company_id == current.company_id)

    # 👇 Regla por rol:
    # - collector: ignoramos employee_id de la query y usamos current.id
    # - admin/manager: usamos el employee_id pasado en la query
    if current.role == "collector":
        effective_employee_id = current.id
    else:
        effective_employee_id = employee_id

    q = q.filter(Loan.employee_id == effective_employee_id)

    if start_utc is not None:
        q = q.filter(Loan.start_date >= start_utc)
    if end_utc_excl is not None:
        q = q.filter(Loan.start_date <  end_utc_excl)

    loans = q.order_by(Loan.start_date.desc(), Loan.id.desc()).all()

    out: List[LoansOut] = []
    today_local = datetime.now(zone).date()

    for loan in loans:
        inst_out: List[InstallmentOut] = []
        for inst in loan.installments:
            dd = inst.due_date
            due_local_date = dd.astimezone(zone).date() if isinstance(dd, datetime) else dd
            is_overdue = (not inst.is_paid) and (due_local_date and due_local_date < today_local)
            inst_out.append(InstallmentOut(
                id=inst.id,
                amount=inst.amount,
                due_date=inst.due_date,
                status=inst.status,
                is_paid=inst.is_paid,
                loan_id=loan.id,
                is_overdue=is_overdue,
                number=inst.number,
                paid_amount=inst.paid_amount,
            ))

        out.append(LoansOut(
            id=loan.id,
            customer_id=loan.customer_id,
            amount=loan.amount,
            total_due=loan.total_due,
            installments_count=loan.installments_count,
            installment_amount=getattr(loan, "installment_amount", None),
            installment_interval_days=getattr(loan, "installment_interval_days", None),
            start_date=loan.start_date,
            status=loan.status,
            company_id=getattr(loan, "company_id", None),
            description=getattr(loan, "description", None),
            collection_day=getattr(loan, "collection_day", None),
            installments=inst_out,
        ))
    return out

class CouponsBatchRequest(BaseModel):
    loan_ids: List[int]
    tz: Optional[str] = "America/Argentina/Tucuman"

@router.post("/coupons.pdf")
def loans_coupons_pdf(
    body: CouponsBatchRequest,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    tz = body.tz or "America/Argentina/Tucuman"
    loan_ids = list(dict.fromkeys([int(x) for x in (body.loan_ids or []) if x]))

    if not loan_ids:
        raise HTTPException(status_code=400, detail="loan_ids vacío")

    # Traemos solo loans de la empresa del user
    loans = (
        db.query(Loan)
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.id.in_(loan_ids))
        .all()
    )

    found_ids = {l.id for l in loans}
    missing = [i for i in loan_ids if i not in found_ids]
    if missing:
        raise HTTPException(status_code=404, detail=f"Préstamos no encontrados o sin acceso: {missing[:20]}")

    items: list[CouponV5Data] = []
    for loan in loans:
        items.append(_coupon_data_for_loan(loan, db, tz))

    # orden estable: en el mismo orden que enviaron desde el front
    by_id = {it.loan_id: it for it in items}
    items_sorted = [by_id[i] for i in loan_ids if i in by_id]

    pdf_bytes = build_coupons_v5_pdf(items_sorted, tz=tz)

    filename = "cupones_prestamos.pdf"
    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.put("/{loan_id}", response_model=LoansOut)
def update_loan(
    loan_id: int,
    body: LoansUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ensure_admin(current)

    loan = (
        db.query(Loan)
        .filter(Loan.id == loan_id, Loan.company_id == current.company_id)
        .first()
    )
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    # ¿Tiene pagos? (no voided)
    payments_count = (
        db.query(func.count(Payment.id))
        .filter(
            Payment.loan_id == loan_id,
            Payment.is_voided.is_(False),
        )
        .scalar()
        or 0
    )

    # =========================
    # 1) Siempre editables
    # =========================
    if body.description is not None:
        loan.description = body.description

    if body.collection_day is not None:
        loan.collection_day = body.collection_day  # 1..7 ISO

    if body.employee_id is not None:
        target_emp = (
            db.query(Employee)
            .filter(Employee.id == body.employee_id, Employee.company_id == current.company_id)
            .first()
        )
        if not target_emp:
            raise HTTPException(status_code=422, detail="employee_id inválido para esta empresa")
        loan.employee_id = target_emp.id


    # =========================
    # 2) Estructurales SOLO si no hay pagos
    # =========================
    structural_fields = (
        body.amount is not None
        or body.installments_count is not None
        or body.installment_interval_days is not None
        or body.start_date is not None
    )

    if payments_count > 0 and structural_fields:
        raise HTTPException(
            status_code=422,
            detail="No se pueden modificar monto/cuotas/fechas porque el préstamo ya tiene pagos. Cancelalo y creá uno nuevo si necesitás cambios.",
        )

    if payments_count == 0 and structural_fields:
        zone = AR_TZ if isinstance(AR_TZ, ZoneInfo) else ZoneInfo("America/Argentina/Tucuman")

        # start_date: si viene, interpretarla en local si es naive
        if body.start_date is not None:
            sd = body.start_date
            if sd.tzinfo is None:
                sd = sd.replace(tzinfo=zone)
            start_local = sd.astimezone(zone)
        else:
            # si no viene, usar el start_date actual del loan en local
            start_local = loan.start_date.astimezone(zone) if loan.start_date else datetime.now(zone)

        # amount / installments_count / interval_days: usar "nuevo si viene" sino el existente
        new_amount = float(body.amount) if body.amount is not None else float(loan.amount)
        new_count = int(body.installments_count) if body.installments_count is not None else int(loan.installments_count)
        new_interval = int(body.installment_interval_days) if body.installment_interval_days is not None else int(loan.installment_interval_days or 0)

        if new_count < 1:
            raise HTTPException(status_code=422, detail="installments_count debe ser >= 1")
        if new_interval < 1:
            raise HTTPException(status_code=422, detail="installment_interval_days es requerido y debe ser >= 1")

        # recalcular
        loan.amount = new_amount
        loan.total_due = new_amount
        loan.installments_count = new_count
        loan.installment_interval_days = new_interval
        loan.installment_amount = round(new_amount / new_count, 2)
        loan.start_date = start_local.astimezone(timezone.utc)

        # borrar cuotas anteriores (sin pagos => todas deberían estar sin pagar)
        db.query(Installment).filter(Installment.loan_id == loan_id).delete(synchronize_session=False)

        # recrear cuotas
        today_local = datetime.now(zone).date()
        for i in range(new_count):
            due_local = start_local + timedelta(days=new_interval * (i + 1))
            local_midnight = due_local.replace(hour=0, minute=0, second=0, microsecond=0)
            due_utc = local_midnight.astimezone(timezone.utc)

            is_overdue = local_midnight.date() < today_local
            init_status = InstallmentStatus.OVERDUE.value if is_overdue else InstallmentStatus.PENDING.value

            db.add(
                Installment(
                    loan_id=loan.id,
                    amount=loan.installment_amount,
                    due_date=due_utc,
                    is_paid=False,
                    status=init_status,
                    number=i + 1,
                    paid_amount=0.0,
                    is_overdue=is_overdue,
                )
            )

    db.add(loan)
    db.commit()
    db.refresh(loan)
    return LoansOut.model_validate(loan)


from datetime import datetime, timezone

@router.post("/{loan_id}/cancel", status_code=200)
def cancel_loan(
    loan_id: int,
    body: Optional[CancelRequest] = None,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Cancela un préstamo:
      - loan.status = "canceled"
      - Cuotas NO pagadas -> status = "canceled" (si había parcial, se mantiene paid_amount tal cual)
      - loan.total_due = 0
      - loan.status_changed_at = now_utc
      - loan.status_reason = reason
    """

    loan = (
        db.query(Loan)
        .filter(Loan.id == loan_id, Loan.company_id == current.company_id)
        .first()
    )
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    reason = (body.reason.strip() if body and body.reason else None)

    installments = (
        db.query(Installment)
        .filter(
            and_(
                Installment.loan_id == loan_id,
                Installment.is_paid.is_(False),
            )
        )
        .all()
    )

    for ins in installments:
        ins.status = InstallmentStatus.CANCELED.value
        db.add(ins)

    loan.status = LoanStatus.CANCELED.value
    loan.total_due = 0.0

    # ✅ NUEVO: ciclo de vida
    loan.status_changed_at = datetime.now(timezone.utc)
    loan.status_reason = reason

    db.add(loan)
    db.commit()

    return {"message": "Préstamo cancelado", "loan_id": loan.id}



class RefinanceResponse(BaseModel):
    remaining_due: float

from datetime import datetime, timezone

class RefinanceResponse(BaseModel):
    remaining_due: float


@router.post("/{loan_id}/refinance", response_model=RefinanceResponse, status_code=200)
def refinance_loan(
    loan_id: int,
    body: Optional[RefinanceRequest] = None,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Refinancia un préstamo:
      - Calcula saldo: Σ(max(amount - paid_amount, 0)) de TODAS las cuotas del loan
      - loan.status = "refinanced"; loan.total_due = 0
      - Cuotas NO pagadas -> status = "refinanced"
      - loan.status_changed_at = now_utc
      - loan.status_reason = reason
      - Devuelve remaining_due para que el front cree el nuevo préstamo con ese monto
    """

    loan = (
        db.query(Loan)
        .filter(Loan.id == loan_id, Loan.company_id == current.company_id)
        .first()
    )
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    reason = (body.reason.strip() if body and body.reason else None)

    installments = db.query(Installment).filter(Installment.loan_id == loan_id).all()

    remaining_due = 0.0
    for ins in installments:
        amount = float(ins.amount or 0.0)
        paid = float(ins.paid_amount or 0.0)
        remaining_due += max(amount - paid, 0.0)

    for ins in installments:
        if not ins.is_paid:
            ins.status = InstallmentStatus.REFINANCED.value
            db.add(ins)

    loan.status = LoanStatus.REFINANCED.value
    loan.total_due = 0.0

    # ✅ NUEVO: ciclo de vida
    loan.status_changed_at = datetime.now(timezone.utc)
    loan.status_reason = reason

    db.add(loan)
    db.commit()

    return RefinanceResponse(remaining_due=remaining_due)


@router.get("/{loan_id}/payments")
def list_payments_by_loan(
    loan_id: int,
    include_voided: bool = True,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """Devuelve pagos del préstamo, más recientes primero. Por defecto incluye anulados."""
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    if getattr(loan, "company_id", None) != current.company_id:
        raise HTTPException(status_code=403, detail="No autorizado")

    q = db.query(Payment).filter(Payment.loan_id == loan_id)
    if not include_voided:
        q = q.filter(Payment.is_voided.is_(False))

    rows = q.order_by(Payment.payment_date.desc(), Payment.id.desc()).all()

    out = []
    for p in rows:
        out.append({
            "id": p.id,
            "loan_id": p.loan_id,
            "amount": float(p.amount) if p.amount is not None else None,
            "payment_date": p.payment_date.isoformat() if p.payment_date else None,
            "payment_type": p.payment_type,
            "description": p.description,
            "is_voided": bool(p.is_voided),
            "voided_at": p.voided_at.isoformat() if getattr(p, "voided_at", None) else None,
            "void_reason": getattr(p, "void_reason", None),
        })
    return out


# ============== PAY ==============
@router.post("/{loan_id}/pay")
def pay_loan_installments(
    loan_id: int,
    payment: LoanPaymentRequest,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    loan = _assert_loan_same_company(loan_id, db, current)

    if payment.amount_paid <= 0:
        raise HTTPException(status_code=400, detail="El monto pagado debe ser mayor a 0")

    if payment.amount_paid > loan.total_due:
        raise HTTPException(status_code=400, detail="El monto a pagar no puede ser mayor al saldo pendiente")

    unpaid_installments = (
        db.query(Installment)
        .filter(Installment.loan_id == loan_id, Installment.is_paid == False)  # noqa: E712
        .order_by(Installment.number)
        .all()
    )
    if not unpaid_installments:
        raise HTTPException(status_code=400, detail="Todas las cuotas ya están pagadas")

    remaining_amount = payment.amount_paid
    cuotas_afectadas = 0

    # ---- aplicar pago en cuotas ----
    for inst in unpaid_installments:
        if remaining_amount <= 0:
            break
        before = remaining_amount
        remaining_amount = inst.register_payment(remaining_amount)
        if before != remaining_amount:
            cuotas_afectadas += 1

    applied_amount = payment.amount_paid - remaining_amount
    if applied_amount <= 0:
        raise HTTPException(status_code=400, detail="No se aplicó ningún pago")

    # ---- Determinar collector_id ----
    # 1. Por defecto: el usuario logueado que está cobrando
    collector_id = current.id

    # 2. Si este payment es legacy o por cualquier razón viene null, usar el cobrador del préstamo
    if not collector_id:
        collector_id = loan.employee_id

    # ---- Registrar Payment ----
    payment_row = Payment(
        amount=float(applied_amount),
        loan_id=loan.id,
        purchase_id=None,
        payment_date=datetime.now(timezone.utc),
        payment_type=payment.payment_type,
        description=(payment.description or "").strip() or None,
        collector_id=collector_id
    )

    db.add(payment_row)

    # ---- Actualizar saldo del loan ----
    loan.total_due = max(loan.total_due - applied_amount, 0.0)
    if loan.total_due == 0:
        loan.status = LoanStatus.PAID.value

    db.commit()

    # ---- Ledger + status ----
    try:
        recompute_ledger_for_loan(db, loan_id)
        db.commit()
        update_status_if_fully_paid(db, loan_id=loan_id, purchase_id=None)
    except Exception:
        db.rollback()
        raise

    return {
        "mensaje": "Pago registrado correctamente",
        "payment_id": payment_row.id,
        "monto_pagado": applied_amount,
        "saldo_pendiente": loan.total_due,
        "cuotas_afectadas": cuotas_afectadas
    }


# ============== GET ONE ==============
@router.get("/{loan_id}", response_model=LoansOut)
def get_loan(
    loan_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Subquery: pagos NO anulados por loan_id
    pay_agg = (
        db.query(
            Payment.loan_id.label("loan_id"),
            func.count(Payment.id).label("payments_count"),
            func.coalesce(func.sum(Payment.amount), 0.0).label("total_paid"),
        )
        .filter(Payment.is_voided == False)  # noqa: E712
        .group_by(Payment.loan_id)
        .subquery()
    )

    cust_name = func.trim(
        func.concat(
            func.coalesce(Customer.first_name, ""),
            literal(" "),
            func.coalesce(Customer.last_name, ""),
        )
    ).label("customer_name")

    row = (
        db.query(
            Loan,
            cust_name,
            Employee.name.label("collector_name"),
            func.coalesce(pay_agg.c.payments_count, 0).label("payments_count"),
            func.coalesce(pay_agg.c.total_paid, 0.0).label("total_paid"),
        )
        .select_from(Loan)
        .join(Customer, Customer.id == Loan.customer_id)
        .outerjoin(Employee, Employee.id == Loan.employee_id)
        .outerjoin(pay_agg, pay_agg.c.loan_id == Loan.id)
        .filter(Loan.id == loan_id)
        .filter(Loan.company_id == current.company_id)
        .first()
    )

    if not row:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    loan = row[0]
    customer_name = (row.customer_name or "").strip() or "-"
    collector_name = row.collector_name or None
    payments_count = int(row.payments_count or 0)
    total_paid = float(row.total_paid or 0.0)

    out = LoansOut.model_validate(loan).model_copy(
        update={
            "customer_name": customer_name,
            "collector_name": collector_name,
            "payments_count": payments_count,
            "total_paid": total_paid,
            # compatibilidad con front viejo
            "employee_name": collector_name,
        }
    )
    return out



# ============== INSTALLMENTS BY LOAN ==============
@router.get("/{loan_id}/installments", response_model=List[InstallmentOut])
def get_installments_for_loan(
    loan_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_loan_same_company(loan_id, db, current)
    installments = (
        db.query(Installment)
        .filter(Installment.loan_id == loan_id)
        .order_by(Installment.id)
        .all()
    )
    if not installments:
        raise HTTPException(status_code=404, detail="No se encontraron cuotas para este préstamo")
    return installments


@router.get("/{loan_id}/coupon.pdf")
def loan_coupon_pdf(
    loan_id: int,
    tz: str = Query("America/Argentina/Tucuman"),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    loan = _assert_loan_same_company(loan_id, db, current)

    # Cargar relaciones si hiciera falta
    # (si lazy no trae, aseguramos con query)
    loan = (
        db.query(Loan)
        .filter(Loan.id == loan_id)
        .first()
    )
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")
    if loan.company_id != current.company_id:
        raise HTTPException(status_code=403, detail="Sin acceso a este préstamo")

    data = _coupon_data_for_loan(loan, db, tz)
    pdf_bytes = build_coupons_v5_pdf([data], tz=tz)

    filename = f"cupon_prestamo_{loan_id}.pdf"
    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )



