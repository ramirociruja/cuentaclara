from typing import List, Optional
from zoneinfo import ZoneInfo
from fastapi import APIRouter, HTTPException, Depends, Query, status
from sqlalchemy.orm import Session
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import func, literal, or_, and_

from app.database.db import get_db
from app.models.models import Loan, Installment, Customer, Company, Payment, Employee
from app.schemas.installments import InstallmentOut
from app.schemas.loans import (
    LoanListItem, LoansOut, LoansCreate, LoansSummaryResponse, LoansUpdate,
    RefinanceRequest, LoanPaymentRequest
)
from app.utils.auth import get_current_user
from app.utils.ledger import recompute_ledger_for_loan
from app.utils.license import ensure_company_active
from app.utils.status import update_status_if_fully_paid
from pydantic import BaseModel

# 🔹 NUEVO: Enums canónicos y normalizadores
from app.constants import InstallmentStatus, LoanStatus
from app.utils.normalize import norm_loan_status
from app.utils.time_windows import parse_iso_aware_utc, local_dates_to_utc_window, AR_TZ
from zoneinfo import ZoneInfo


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

    needs_customer = (employee_id is not None) or (province is not None) or (not hasattr(Loan, "company_id"))
    if hasattr(Loan, "company_id") and not needs_customer:
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = q.join(Customer, Loan.customer_id == Customer.id)\
             .filter(Customer.company_id == current.company_id)
        if employee_id is not None:
            q = q.filter(Customer.employee_id == employee_id)
        if province is not None:
            q = q.filter(Customer.province == province)

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





@router.get("/", response_model=List[LoanListItem])
def list_loans(
    employee_id: Optional[int] = Query(None),
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
    # 1) SUBQUERY de IDs (sin ORDER BY ni DISTINCT ON problemático)
    # ============================================================
    needs_customer = (employee_id is not None) or (province is not None) or (not hasattr(Loan, "company_id"))

    base_ids = db.query(Loan.id)

    if hasattr(Loan, "company_id") and not needs_customer:
        # Podemos filtrar por empresa directamente en Loan sin join
        base_ids = base_ids.filter(Loan.company_id == current.company_id)
    else:
        # Necesitamos Customer para filtrar por company/employee/province
        base_ids = (
            base_ids.join(Customer, Loan.customer_id == Customer.id)
                    .filter(Customer.company_id == current.company_id)
        )
        if employee_id is not None:
            base_ids = base_ids.filter(Customer.employee_id == employee_id)
        if province is not None:
            base_ids = base_ids.filter(Customer.province == province)

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
    # 2) QUERY FINAL (trae columnas, joinea con Customer y ordena)
    # ============================================================
    q2 = (
        db.query(
            Loan.id.label("id"),
            func.coalesce(Loan.amount, 0.0).label("amount"),
            Loan.start_date.label("start_date"),
            cust_name,
            Customer.province.label("customer_province"),
        )
        .join(ids_subq, ids_subq.c.id == Loan.id)                 # restringe a IDs únicos
        .join(Customer, Loan.customer_id == Customer.id)          # para enriquecer con datos del cliente
    )

    rows = (
        q2.order_by(Loan.start_date.desc(), Loan.id.desc())       # orden correcto por fecha
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

    zone = AR_TZ  # si querés parametrizar por compañía/usuario, podés hacerlo
    # start_date: si viene, normalizá a UTC; si no, now UTC
    if loan.start_date:
        sd = loan.start_date
        if sd.tzinfo is None:
            sd = sd.replace(tzinfo=timezone.utc)
        start_date_utc = sd.astimezone(timezone.utc)
    else:
        start_date_utc = datetime.now(timezone.utc)

    new_loan = Loan(
        **loan.model_dump(exclude={"installments", "start_date", "company_id"}),
        start_date=start_date_utc,
        total_due=loan.amount,
        company_id=current.company_id,
    )

    # installment_amount
    installment_amount = round(loan.amount / loan.installments_count, 2)
    if hasattr(Loan, "installment_amount"):
        new_loan.installment_amount = installment_amount

    db.add(new_loan)
    db.commit()
    db.refresh(new_loan)

    # Crear cuotas automáticamente
    for i in range(loan.installments_count):
        if loan.frequency == "weekly":
            due_local = start_date_utc.astimezone(zone) + timedelta(weeks=i + 1)
        else:
            # mensual simple (4 semanas aprox)
            due_local = start_date_utc.astimezone(zone) + timedelta(weeks=(i + 1) * 4)

        # due_date = midnight LOCAL → UTC
        local_midnight = due_local.replace(hour=0, minute=0, second=0, microsecond=0)
        due_date_utc = local_midnight.astimezone(timezone.utc)

        # status inicial según día local
        today_local = datetime.now(zone).date()
        is_overdue = (local_midnight.date() < today_local)
        init_status = InstallmentStatus.OVERDUE.value if is_overdue else InstallmentStatus.PENDING.value

        installment = Installment(
            loan_id=new_loan.id,
            amount=installment_amount,
            due_date=due_date_utc,      # 👈 UTC
            is_paid=False,
            status=init_status,          # EN canónico
            number=i + 1,
            paid_amount=0.0,
            is_overdue=is_overdue,
        )
        db.add(installment)

    db.commit()
    return new_loan


# ============== LIST BY CUSTOMER ==============
@router.get("/customer/{customer_id}", response_model=list[LoansOut])
def get_loans_by_customer(
    customer_id: int,
    tz: Optional[str] = Query(None),                     # 👈 NUEVO
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_customer_same_company(customer_id, db, current)
    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()

    q = db.query(Loan).filter(Loan.customer_id == customer_id)
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)

    loans = q.all()
    if not loans:
        return []

    loan_outs: list[LoansOut] = []
    for loan in loans:
        installments_out: list[InstallmentOut] = []

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

        loan_outs.append(LoansOut(
            id=loan.id,
            customer_id=loan.customer_id,
            amount=loan.amount,
            total_due=loan.total_due,
            installments_count=loan.installments_count,
            installment_amount=getattr(loan, "installment_amount", None),
            frequency=loan.frequency,
            start_date=loan.start_date,
            status=loan.status,
            company_id=getattr(loan, "company_id", None),
            installments=installments_out,
        ))

    return loan_outs


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

    q = db.query(Loan)
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = q.join(Customer, Loan.customer_id == Customer.id)\
             .filter(Customer.company_id == current.company_id)

    q = q.join(Customer, Loan.customer_id == Customer.id)\
         .filter(Customer.employee_id == employee_id)

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
            frequency=loan.frequency,
            start_date=loan.start_date,
            status=loan.status,
            company_id=getattr(loan, "company_id", None),
            description=getattr(loan, "description", None),
            collection_day=getattr(loan, "collection_day", None),
            installments=inst_out,
        ))
    return out


@router.put("/{loan_id}", response_model=LoansOut)
def update_loan(
    loan_id: int,
    body: LoansUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    loan = db.query(Loan).filter(
        Loan.id == loan_id,
        Loan.company_id == current.company_id
    ).first()
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    # Solo campos seguros
    if body.description is not None:
        loan.description = body.description
    if body.collection_day is not None:
        loan.collection_day = body.collection_day
    if body.status is not None:
        # 🔹 normalizamos ES/EN a EN canónico
        loan.status = norm_loan_status(body.status).value

    db.add(loan)
    db.commit()
    db.refresh(loan)
    return LoansOut.from_orm(loan)


class CancelRequest(BaseModel):
    reason: str | None = None

@router.post("/{loan_id}/cancel", status_code=200)
def cancel_loan(
    loan_id: int,
    body: CancelRequest | None = None,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Cancela un préstamo:
      - loan.status = "canceled"
      - Cuotas NO pagadas -> status = "canceled" (si había parcial, se mantiene paid_amount tal cual)
      - loan.total_due = 0
    """
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    # Marcar cuotas pendientes como Canceladas (EN canónico)
    installments = (
        db.query(Installment)
        .filter(and_(Installment.loan_id == loan_id, Installment.is_paid.is_(False)))
        .all()
    )
    for ins in installments:
        ins.status = InstallmentStatus.CANCELED.value
        db.add(ins)

    loan.status = LoanStatus.CANCELED.value
    loan.total_due = 0.0
    db.add(loan)

    db.commit()
    return {"message": "Préstamo cancelado", "loan_id": loan.id}


class RefinanceResponse(BaseModel):
    remaining_due: float

@router.post("/{loan_id}/refinance", response_model=RefinanceResponse, status_code=200)
def refinance_loan(
    loan_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Refinancia un préstamo:
      - Calcula saldo: Σ(max(amount - paid_amount, 0)) de TODAS las cuotas del loan
      - loan.status = "refinanced"; loan.total_due = 0
      - Cuotas NO pagadas -> status = "refinanced"
      - Devuelve remaining_due para que el front cree el nuevo préstamo con ese monto
    """
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    installments = db.query(Installment).filter(Installment.loan_id == loan_id).all()
    remaining_due = 0.0
    for ins in installments:
        amount = float(ins.amount or 0.0)
        paid = float(ins.paid_amount or 0.0)
        remaining_due += max(amount - paid, 0.0)

    # Marcar cuotas no pagadas como Refinanciada (EN canónico)
    for ins in installments:
        if not ins.is_paid:
            ins.status = InstallmentStatus.REFINANCED.value
            db.add(ins)

    loan.status = LoanStatus.REFINANCED.value
    loan.total_due = 0.0
    db.add(loan)

    db.commit()
    return RefinanceResponse(remaining_due=remaining_due)

@router.get("/{loan_id}/payments")
def list_payments_by_loan(
    loan_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """Devuelve los pagos del préstamo (más recientes primero)."""
    loan = db.query(Loan).get(loan_id)
    if not loan:
        raise HTTPException(status_code=404, detail="Préstamo no encontrado")

    rows = (
        db.query(Payment)
        .filter(Payment.loan_id == loan_id, Payment.is_voided.is_(False))
        .order_by(Payment.payment_date.desc(), Payment.id.desc())
        .all()
    )
    out = []
    for p in rows:
        out.append({
            "id": p.id,
            "loan_id": p.loan_id,
            "amount": p.amount,
            "payment_date": p.payment_date.isoformat() if p.payment_date else None,
            "payment_type": p.payment_type,
            "description": p.description,
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

    # Registrar Payment
    payment_row = Payment(
        amount=float(applied_amount),
        loan_id=loan.id,
        purchase_id=None,
        payment_date=datetime.now(timezone.utc),
        payment_type=payment.payment_type,
        description=(payment.description or "").strip() or None
    )
    db.add(payment_row)

    # Actualizar saldo y (si queda en 0) estado del préstamo
    loan.total_due = max(loan.total_due - applied_amount, 0.0)
    if loan.total_due == 0:
        loan.status = LoanStatus.PAID.value  # 👈 canónico

    db.commit()
    try:
        # recalcula paid_amount/status de cuotas y CREA PaymentAllocation
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
    loan = _assert_loan_same_company(loan_id, db, current)
    return loan

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
