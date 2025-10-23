from typing import List, Optional
from zoneinfo import ZoneInfo
from fastapi import APIRouter, HTTPException, Depends, Query, status
from sqlalchemy.orm import Session
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import func, or_, and_

from app.database.db import get_db
from app.models.models import Loan, Installment, Customer, Company, Payment, Employee
from app.schemas.installments import InstallmentOut
from app.schemas.loans import (
    LoansOut, LoansCreate, LoansSummaryResponse, LoansUpdate,
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

router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],  # 👈 exige Bearer válido en todo el router
)

# ---------- helpers fecha ----------
from datetime import date as date_cls, datetime, timezone

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
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Resume cantidad y monto total de Loans con start_date en el rango.
    Filtra SIEMPRE por la empresa del token y opcionalmente por employee_id.
    """
    df, dt = _normalize_range(date_from, date_to)

    q = db.query(func.count(Loan.id), func.coalesce(func.sum(Loan.amount), 0.0))
    # 👇 filtro por empresa
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = q.join(Customer, Loan.customer_id == Customer.id).filter(Customer.company_id == current.company_id)

    if employee_id is not None:
        q = q.join(Customer, Loan.customer_id == Customer.id).filter(Customer.employee_id == employee_id)
    if df is not None:
        q = q.filter(Loan.start_date >= df)
    if dt is not None:
        q = q.filter(Loan.start_date <= dt)

    count, amount = q.one()
    return LoansSummaryResponse(count=int(count or 0), amount=float(amount or 0.0))

# ============== CREATE ==============
@router.post("/createLoan/", response_model=LoansOut, status_code=status.HTTP_201_CREATED)
def create_loan(
    loan: LoansCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Validar cliente y que pertenezca a la empresa del token
    customer = _assert_customer_same_company(loan.customer_id, db, current)

    # Forzar empresa desde el token (ignoramos company_id del body)
    start_date = loan.start_date or datetime.utcnow()
    new_loan = Loan(
        **loan.model_dump(exclude={"installments", "start_date", "company_id"}),
        start_date=start_date,
        total_due=loan.amount,
        company_id=current.company_id,     # 👈 forzado
    )

    # Calcular y (si existe la columna) setear installment_amount
    installment_amount = round(loan.amount / loan.installments_count, 2)
    if hasattr(Loan, "installment_amount"):
        new_loan.installment_amount = installment_amount

    db.add(new_loan)
    db.commit()
    db.refresh(new_loan)

    # Crear cuotas automáticamente (EN canónico)
    for i in range(loan.installments_count):
        if loan.frequency == "weekly":
            due_date = start_date + timedelta(weeks=i + 1)
        else:
            # mensual simple (aprox 4 semanas)
            due_date = start_date + timedelta(weeks=(i + 1) * 4)
    
    # comparar por fecha (no datetime)
        due_only = due_date.date() if isinstance(due_date, datetime) else due_date
        today = datetime.now(ZoneInfo("America/Argentina/Tucuman")).date()
        is_overdue = (due_only < today)
        init_status = InstallmentStatus.OVERDUE.value if is_overdue else InstallmentStatus.PENDING.value

        installment = Installment(
            loan_id=new_loan.id,
            amount=installment_amount,
            due_date=due_date,
            is_paid=False,
            status= init_status,
            number=i + 1,
            paid_amount=0.0,
            is_overdue=False,
        )
        db.add(installment)

    db.commit()
    return new_loan

# ============== LIST BY CUSTOMER ==============
@router.get("/customer/{customer_id}", response_model=list[LoansOut])
def get_loans_by_customer(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_customer_same_company(customer_id, db, current)

    q = db.query(Loan).filter(Loan.customer_id == customer_id)
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)

    loans = q.all()
    if not loans:
        return []

    loan_outs: list[LoansOut] = []
    for loan in loans:
        installments_out: list[InstallmentOut] = []
        for installment in loan.installments:
            is_overdue = (
                installment.due_date.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc)
                and not installment.is_paid
            )
            installments_out.append(InstallmentOut(
                id=installment.id,
                amount=installment.amount,
                due_date=installment.due_date,
                status=installment.status,  # ya en EN canónico
                is_paid=installment.is_paid,
                loan_id=loan.id,
                is_overdue=is_overdue,
                number=installment.number,
                paid_amount=installment.paid_amount,
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
            status=loan.status,  # EN canónico
            company_id=getattr(loan, "company_id", None),
            installments=installments_out,
        ))

    return loan_outs

@router.get("/by-employee", response_model=List[LoansOut])
def get_loans_by_employee(
    employee_id: int = Query(...),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    df, dt = _normalize_range(date_from, date_to)

    q = db.query(Loan)
    if hasattr(Loan, "company_id"):
        q = q.filter(Loan.company_id == current.company_id)
    else:
        q = q.join(Customer, Loan.customer_id == Customer.id)\
             .filter(Customer.company_id == current.company_id)

    q = q.join(Customer, Loan.customer_id == Customer.id)\
         .filter(Customer.employee_id == employee_id)

    if df is not None:
        q = q.filter(Loan.start_date >= df)
    if dt is not None:
        q = q.filter(Loan.start_date <= dt)

    loans = q.order_by(Loan.start_date.desc(), Loan.id.desc()).all()

    out: List[LoansOut] = []
    for loan in loans:
        # start_date -> date (no datetime)
        sd = loan.start_date
        if isinstance(sd, datetime):
            sd = sd.date()
        elif sd is None:
            sd = None  # respeta Optional[date]

        # company_id garantizado (si en modelo es obligatorio)
        comp_id = getattr(loan, "company_id", None) or current.company_id

        inst_out: List[InstallmentOut] = []
        for inst in loan.installments:
            is_overdue = (
                inst.due_date and
                inst.due_date.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc) and
                not inst.is_paid
            )
            inst_out.append(InstallmentOut(
                id=inst.id,
                amount=inst.amount,
                due_date=inst.due_date,
                status=inst.status,  # EN canónico
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
            start_date=sd,
            status=loan.status,  # EN canónico
            company_id=comp_id,
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
        payment_date=datetime.utcnow(),
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
