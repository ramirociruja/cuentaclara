from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, status, UploadFile, File
from pydantic import BaseModel, EmailStr
from sqlalchemy import func
from sqlalchemy.orm import Session
from dateutil.relativedelta import relativedelta
from app.database.db import get_db
from app.models.models import (
    Company,
    Employee,
    Customer,
    Loan,
    Installment,
    Payment,
    PaymentAllocation,
    OnboardingImportSession,
)

from app.constants import InstallmentStatus, LoanStatus
from app.utils.time_windows import AR_TZ
from app.schemas.companies import Company as CompanyOut
from app.schemas.employee import (
    EmployeeCreateIn,
    EmployeeOut,
    EmployeePasswordResetIn,
    EmployeeUpdateIn,
)

from app.schemas.superadmin_onboarding import (
    OnboardingCommitCounts,
    OnboardingCommitOut,
    CommitIn,
)
from app.utils.auth import get_current_user, hash_password

from app.services.onboarding_import_validate import validate_onboarding_xlsx


router = APIRouter(
    prefix="/superadmin",
    tags=["SuperAdmin"],
)


# -----------------------------
# 🔐 Guard para superadmin real
# -----------------------------
def ensure_superadmin(
    current: Employee = Depends(get_current_user),
) -> Employee:
    if (current.role or "").lower() != "superadmin":
        raise HTTPException(
            status_code=403,
            detail="Solo superadmin puede acceder a este recurso",
        )
    return current


# ==================================
# 📌 INPUTS / OUTPUTS
# ==================================

class CompanyCreateIn(BaseModel):
    name: str
    license_days: int = 30
    admin_name: str
    admin_email: EmailStr
    admin_phone: str | None = None
    admin_password: str


class LicenseExtendIn(BaseModel):
    days: int = 30


class SuspendCompanyIn(BaseModel):
    reason: str | None = None


class SuperAdminSummary(BaseModel):
    active_companies: int
    suspended_companies: int
    expired_companies: int
    total_employees: int


# ==================================
# 📌 EMPRESAS
# ==================================

@router.get("/companies", response_model=List[CompanyOut])
def admin_list_companies(
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    return db.query(Company).order_by(Company.id).all()


@router.post("/companies", response_model=CompanyOut, status_code=status.HTTP_201_CREATED)
def admin_create_company(
    payload: CompanyCreateIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    now = datetime.now(timezone.utc)

    # Crear empresa
    company = Company(
        name=payload.name,
        service_status="active",
        license_expires_at=now + timedelta(days=payload.license_days),
        suspended_at=None,
        suspension_reason=None,
    )
    db.add(company)
    db.commit()
    db.refresh(company)

    # Normalizar email
    normalized_email = payload.admin_email.lower().strip()

    # Verificar que no exista un empleado con ese email
    existing = (
        db.query(Employee)
        .filter(Employee.email.ilike(normalized_email))
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=400,
            detail="Ya existe un empleado con ese email",
        )

    # Crear admin inicial de la empresa
    admin = Employee(
        name=payload.admin_name.strip(),
        email=normalized_email,
        phone=payload.admin_phone,
        role="admin",
        password=hash_password(payload.admin_password),
        company_id=company.id,
        created_at=now,
    )
    db.add(admin)
    db.commit()

    return company


@router.post("/companies/{company_id}/extend-license", response_model=CompanyOut)
def admin_extend_license(
    company_id: int,
    payload: LicenseExtendIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    now = datetime.now(timezone.utc)
    old_exp = company.license_expires_at or now
    if old_exp < now:
        old_exp = now

    new_exp = old_exp + timedelta(days=payload.days)
    company.license_expires_at = new_exp

    # Si estaba expirada y ahora queda vigente, reactivar (si no está suspendida manualmente)
    if getattr(company, "service_status", None) == "expired" and new_exp > now:
        company.service_status = "active"

    db.add(company)
    db.commit()
    db.refresh(company)
    return company


@router.post("/companies/{company_id}/suspend", response_model=CompanyOut)
def admin_suspend_company(
    company_id: int,
    payload: SuspendCompanyIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    if company.service_status == "suspended":
        raise HTTPException(status_code=400, detail="La empresa ya está suspendida")

    company.service_status = "suspended"
    company.suspended_at = datetime.now(timezone.utc)
    company.suspension_reason = payload.reason or "Suspensión manual desde panel SuperAdmin"

    db.add(company)
    db.commit()
    db.refresh(company)
    return company


@router.post("/companies/{company_id}/reactivate", response_model=CompanyOut)
def admin_reactivate_company(
    company_id: int,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    if company.service_status == "active":
        raise HTTPException(status_code=400, detail="La empresa ya está activa")

    company.service_status = "active"
    company.suspended_at = None
    company.suspension_reason = None

    db.add(company)
    db.commit()
    db.refresh(company)
    return company


# ==================================
# 📌 ONBOARDING IMPORT (VALIDATE)
# ==================================

@router.post("/companies/{company_id}/onboarding-import/validate")
async def superadmin_validate_onboarding_import(
    company_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    if not file.filename or not file.filename.lower().endswith(".xlsx"):
        raise HTTPException(status_code=400, detail="Solo se acepta .xlsx")

    raw = await file.read()
    result = validate_onboarding_xlsx(raw)

    batch_id = uuid.uuid4()
    expires_at = datetime.now(timezone.utc) + timedelta(hours=6)

    session = OnboardingImportSession(
        id=batch_id,
        company_id=company_id,
        original_filename=file.filename,
        status="validated",
        payload_json=result["payload"],
        summary_json=result["summary"],
        errors_json=result["errors"],
        warnings_json=result["warnings"],
        expires_at=expires_at,
    )
    db.add(session)
    db.commit()

    return {
        "batch_token": str(batch_id),
        "summary": result["summary"],
        "errors": result["errors"],
        "warnings": result["warnings"],
    }


# ==================================
# 📌 EMPLEADOS
# ==================================

@router.get("/employees", response_model=list[EmployeeOut])
def admin_list_employees(
    company_id: int | None = Query(None),
    role: str | None = Query(None),
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    q = db.query(Employee)

    if company_id is not None:
        q = q.filter(Employee.company_id == company_id)

    if role:
        q = q.filter(Employee.role == role)

    return q.order_by(Employee.id).all()


@router.post("/employees", response_model=EmployeeOut, status_code=status.HTTP_201_CREATED)
def admin_create_employee(
    payload: EmployeeCreateIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    # Verificar que la empresa exista
    company = db.get(Company, payload.company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no existe")

    # Normalizar email
    normalized_email = payload.email.lower().strip()

    # Verificar email duplicado
    exists = (
        db.query(Employee)
        .filter(Employee.email.ilike(normalized_email))
        .first()
    )
    if exists:
        raise HTTPException(status_code=400, detail="Ese email ya está usado")

    emp = Employee(
        name=payload.name.strip(),
        email=normalized_email,
        phone=payload.phone,
        role=payload.role,
        password=hash_password(payload.password),
        company_id=payload.company_id,
        created_at=datetime.now(timezone.utc),
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp


@router.get("/employees/{employee_id}", response_model=EmployeeOut)
def admin_get_employee_detail(
    employee_id: int,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    return employee


@router.put("/employees/{employee_id}", response_model=EmployeeOut)
def admin_update_employee(
    employee_id: int,
    payload: EmployeeUpdateIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    # Email
    if payload.email is not None:
        new_email = payload.email.lower().strip()
        if new_email != employee.email:
            existing = (
                db.query(Employee)
                .filter(Employee.email.ilike(new_email))
                .first()
            )
            if existing:
                raise HTTPException(status_code=400, detail="Ya existe un empleado con ese email")
            employee.email = new_email

    # Company
    if payload.company_id is not None:
        company = db.get(Company, payload.company_id)
        if not company:
            raise HTTPException(status_code=404, detail="Empresa no encontrada")
        employee.company_id = payload.company_id

    if payload.name is not None:
        employee.name = payload.name.strip()
    if payload.role is not None:
        employee.role = payload.role
    if payload.phone is not None:
        employee.phone = payload.phone

    db.add(employee)
    db.commit()
    db.refresh(employee)
    return employee


@router.post("/employees/{employee_id}/reset-password", status_code=status.HTTP_204_NO_CONTENT)
def admin_reset_employee_password(
    employee_id: int,
    payload: EmployeePasswordResetIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    if len(payload.new_password) < 4:
        raise HTTPException(status_code=400, detail="La contraseña debe tener al menos 4 caracteres.")

    employee.password = hash_password(payload.new_password)
    db.add(employee)
    db.commit()
    return  # 204 sin body


# ==================================
# 📌 SUMMARY
# ==================================

@router.get("/summary", response_model=SuperAdminSummary)
def superadmin_summary(
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    active = db.query(func.count(Company.id)).filter(Company.service_status == "active").scalar() or 0
    suspended = db.query(func.count(Company.id)).filter(Company.service_status == "suspended").scalar() or 0
    expired = db.query(func.count(Company.id)).filter(Company.service_status == "expired").scalar() or 0
    total_emps = db.query(func.count(Employee.id)).scalar() or 0

    return SuperAdminSummary(
        active_companies=active,
        suspended_companies=suspended,
        expired_companies=expired,
        total_employees=total_emps,
    )


@router.post(
    "/companies/{company_id}/onboarding-import/commit",
    response_model=OnboardingCommitOut,
)
def superadmin_commit_onboarding_import(
    company_id: int,
    payload: CommitIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    # 1) Buscar sesión por UUID
    try:
        batch_uuid = uuid.UUID(payload.batch_token)
    except Exception:
        raise HTTPException(status_code=400, detail="batch_token inválido (UUID esperado)")

    session = (
        db.query(OnboardingImportSession)
        .filter(OnboardingImportSession.id == batch_uuid)
        .filter(OnboardingImportSession.company_id == company_id)
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Batch token inválido o no encontrado")

    now = datetime.now(timezone.utc)

    if session.expires_at and session.expires_at < now:
        raise HTTPException(status_code=400, detail="Batch token expirado; volvé a validar el Excel")

    if session.status != "validated":
        raise HTTPException(status_code=400, detail=f"El batch está en estado {session.status}")

    data = session.payload_json or {}
    customers_rows = data.get("customers", []) or []
    loans_rows = data.get("loans", []) or []
    payments_rows = data.get("payments", []) or []

    # Owner “default” para Customer.employee_id (por consistencia con tu modelo/índices)
    default_owner = (
        db.query(Employee)
        .filter(Employee.company_id == company_id)
        .order_by(Employee.id.asc())
        .first()
    )
    if not default_owner:
        raise HTTPException(status_code=400, detail="La empresa no tiene empleados; creá al menos 1 empleado antes")

    def _get_employee_id_by_email(email: str | None) -> int | None:
        if not email:
            return None
        e = (
            db.query(Employee)
            .filter(Employee.company_id == company_id)
            .filter(Employee.email.ilike(email.strip()))
            .first()
        )
        return e.id if e else None

    def _parse_iso_dt(s: str | None) -> datetime | None:
        if not s:
            return None
        try:
            dt = datetime.fromisoformat(s)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            return None

    counts = OnboardingCommitCounts()

    try:
        customer_ref_to_id: dict[str, int] = {}
        loan_ref_to_id: dict[str, int] = {}
        loan_id_to_installments: dict[int, list[Installment]] = {}

        # =========================
        # 1) Customers
        # =========================
        for c in customers_rows:
            cref = (c.get("customer_ref") or "").strip()
            if not cref:
                raise HTTPException(status_code=400, detail="Customers: customer_ref vacío")

            customer = Customer(
                company_id=company_id,
                employee_id=default_owner.id,
                first_name=(c.get("first_name") or "").strip(),
                last_name=(c.get("last_name") or "").strip(),
                dni=(c.get("dni") or None),
                phone=(c.get("phone") or None),
                email=(c.get("email") or None),
                address=(c.get("address") or None),
                province=(c.get("province") or None),
                created_at=now,
            )
            db.add(customer)
            db.flush()
            customer_ref_to_id[cref] = customer.id
            counts.customers_created += 1

        # =========================
        # 2) Loans + 3) Installments
        # =========================
        for l in loans_rows:
            lref = (l.get("loan_ref") or "").strip()
            cref = (l.get("customer_ref") or "").strip()
            if not lref or not cref:
                raise HTTPException(status_code=400, detail="Loans: loan_ref/customer_ref vacío")

            customer_id = customer_ref_to_id.get(cref)
            if not customer_id:
                raise HTTPException(status_code=400, detail=f"Loans: customer_ref no resuelto: {cref}")

            employee_id = _get_employee_id_by_email(l.get("employee_email")) or default_owner.id
            start_dt = _parse_iso_dt(l.get("start_date")) or now

            loan = Loan(
                company_id=company_id,
                customer_id=customer_id,
                employee_id=employee_id,
                amount=float(l.get("amount") or 0),
                total_due=float(l.get("total_due") or 0),
                installments_count=int(l.get("installments_count") or 0),
                installment_amount=float(l.get("installment_amount") or 0),
                frequency=(l.get("frequency") or "weekly"),
                start_date=start_dt,
                status=(l.get("status") or LoanStatus.ACTIVE.value),
                description=l.get("description"),
                collection_day=l.get("collection_day"),
            )
            db.add(loan)
            db.flush()
            loan_ref_to_id[lref] = loan.id
            counts.loans_created += 1

            # Generación de cuotas:
            # - weekly: +1 semana por cuota
            # - monthly: +1 mes por cuota (cuota 1 vence 1 mes después de start_date)
            base_local = start_dt.astimezone(AR_TZ).replace(hour=0, minute=0, second=0, microsecond=0)

            n = loan.installments_count
            for i in range(n):
                if loan.frequency == "weekly":
                    due_local = base_local + timedelta(weeks=i + 1)
                else:
                    due_local = base_local + relativedelta(months=i + 1)

                due_utc = due_local.astimezone(timezone.utc)

                today_local = datetime.now(AR_TZ).date()
                is_overdue = (due_local.date() < today_local)

                inst = Installment(
                    loan_id=loan.id,
                    number=i + 1,
                    due_date=due_utc,
                    amount=loan.installment_amount,
                    paid_amount=0.0,
                    is_paid=False,
                    is_overdue=is_overdue,
                    status=InstallmentStatus.OVERDUE.value if is_overdue else InstallmentStatus.PENDING.value,
                )
                db.add(inst)
                counts.installments_created += 1
                loan_id_to_installments.setdefault(loan.id, []).append(inst)

        db.flush()

        for lid, insts in loan_id_to_installments.items():
            insts.sort(key=lambda x: (x.due_date, x.number))

        # =========================
        # 4) Payments + 5) Allocations
        # =========================
        for p in payments_rows:
            pref = (p.get("payment_ref") or "").strip()
            lref = (p.get("loan_ref") or "").strip()
            if not pref or not lref:
                raise HTTPException(status_code=400, detail="Payments: payment_ref/loan_ref vacío")

            loan_id = loan_ref_to_id.get(lref)
            if not loan_id:
                raise HTTPException(status_code=400, detail=f"Payments: loan_ref no resuelto: {lref}")

            loan_obj = db.get(Loan, loan_id)
            if not loan_obj:
                raise HTTPException(status_code=400, detail=f"Payments: loan_id no encontrado: {loan_id}")

            collector_id = (
                _get_employee_id_by_email(p.get("collector_email"))
                or loan_obj.employee_id
                or default_owner.id
            )

            payment_dt = _parse_iso_dt(p.get("payment_date")) or now
            amount = float(p.get("amount") or 0)
            if amount <= 0:
                raise HTTPException(
                    status_code=400,
                    detail=f"Payments: amount inválido (<=0) en payment_ref={pref}",
                )

            payment = Payment(
                loan_id=loan_id,
                amount=amount,
                payment_date=payment_dt,
                payment_type=p.get("payment_type"),
                description=p.get("description"),
                collector_id=collector_id,
                is_voided=False,
            )
            db.add(payment)
            db.flush()
            counts.payments_created += 1

            remaining = amount
            installments = loan_id_to_installments.get(loan_id, [])
            if not installments:
                raise HTTPException(
                    status_code=400,
                    detail=f"Payments: el préstamo loan_ref={lref} no tiene cuotas generadas",
                )

            # Distribuir sobre cuotas en orden
            for inst in installments:
                if remaining <= 0:
                    break

                before = float(inst.paid_amount or 0.0)
                remaining = inst.register_payment(remaining)
                after = float(inst.paid_amount or 0.0)
                applied = after - before

                if applied > 0:
                    alloc = PaymentAllocation(
                        payment_id=payment.id,
                        installment_id=inst.id,
                        amount_applied=applied,
                        created_at=now,
                    )
                    db.add(alloc)
                    counts.payment_allocations_created += 1

            # Bloqueo si sobra plata
            if remaining > 0.000001:
                applied_total = amount - remaining
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Pago excede la deuda del préstamo: "
                        f"payment_ref={pref}, loan_ref={lref}. "
                        f"Monto pago={amount:.2f}, aplicado={applied_total:.2f}, excedente={remaining:.2f}. "
                        f"Corregí el Excel y reintentá."
                    ),
                )
        # =========================
            # 6) Recalcular saldo de cada loan (total_due) según cuotas
            # =========================
            EPS = 0.000001

            for lref, loan_id in loan_ref_to_id.items():
                loan_obj = db.get(Loan, loan_id)
                if not loan_obj:
                    continue

                insts = loan_id_to_installments.get(loan_id, [])
                # Si por alguna razón no está en el dict, lo recalculamos desde DB
                if not insts:
                    insts = (
                        db.query(Installment)
                        .filter(Installment.loan_id == loan_id)
                        .order_by(Installment.number.asc())
                        .all()
                    )

                remaining = 0.0
                for inst in insts:
                    amt = float(inst.amount or 0.0)
                    paid = float(inst.paid_amount or 0.0)
                    remaining += max(0.0, amt - paid)

                # Normalizar flotantes
                if remaining < EPS:
                    remaining = 0.0

                loan_obj.total_due = remaining

                # Opcional: estado del préstamo según saldo
                if remaining == 0.0:
                    loan_obj.status = LoanStatus.PAID.value
                else:
                    # Si querés mantener status del Excel, no lo forces.
                    # Si preferís normalizar:
                    if (loan_obj.status or "") == LoanStatus.PAID.value:
                        loan_obj.status = LoanStatus.ACTIVE.value
                        
        session.status = "committed"

        db.commit()

        return OnboardingCommitOut(
            import_batch_id=str(session.id),
            created_counts=counts,
            created_ids={"company_id": company_id},
            summary=session.summary_json,
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error al importar: {str(e)}")
