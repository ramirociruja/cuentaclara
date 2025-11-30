from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from typing import List

from app.database.db import get_db
from app.models.models import Company, Employee
from app.schemas.companies import Company as CompanyOut
from app.schemas.employee import EmployeeOut
from app.utils.auth import hash_password
from app.utils.auth import get_current_user


router = APIRouter(
    prefix="/superadmin",
    tags=["SuperAdmin"]
)


# -----------------------------
# 🔐 Guard para superadmin real
# -----------------------------
def ensure_superadmin(
    current: Employee = Depends(get_current_user)
) -> Employee:
    if (current.role or "").lower() != "superadmin":
        raise HTTPException(
            status_code=403,
            detail="Solo superadmin puede acceder a este recurso"
        )
    return current


# ==================================
# 📌 EMPRESAS
# ==================================

# 1) Listar todas las empresas
@router.get("/companies", response_model=List[CompanyOut])
def admin_list_companies(
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    return db.query(Company).order_by(Company.id).all()


# 2) Crear empresa + admin inicial
from pydantic import BaseModel, EmailStr

class CompanyCreateIn(BaseModel):
    name: str
    license_days: int = 30
    admin_name: str
    admin_email: EmailStr
    admin_phone: str | None = None
    admin_password: str


@router.post("/companies", response_model=CompanyOut, status_code=201)
def admin_create_company(
    payload: CompanyCreateIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    now = datetime.now(timezone.utc)

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

    # Crear admin de empresa
    normalized_email = payload.admin_email.lower().strip()
    existing = (
        db.query(Employee)
        .filter(Employee.email.ilike(normalized_email))
        .first()
    )
    if existing:
        raise HTTPException(400, "Ya existe un empleado con ese email")

    admin = Employee(
        name=payload.admin_name,
        email=normalized_email,
        phone=payload.admin_phone,
        role="admin",
        password=hash_password(payload.admin_password),
        company_id=company.id
    )
    db.add(admin)
    db.commit()

    return company


# 3) Extender licencia
class LicenseExtendIn(BaseModel):
    days: int = 30


@router.post("/companies/{company_id}/extend-license", response_model=CompanyOut)
def admin_extend_license(
    company_id: int,
    payload: LicenseExtendIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(404, "Empresa no encontrada")

    now = datetime.now(timezone.utc)

    old_exp = company.license_expires_at or now
    if old_exp < now:
        old_exp = now

    company.license_expires_at = old_exp + timedelta(days=payload.days)
    db.commit()
    db.refresh(company)
    return company


# 4) Suspender / Reactivar empresa
class SuspendIn(BaseModel):
    reason: str | None = None


@router.post("/companies/{company_id}/suspend", response_model=CompanyOut)
def admin_suspend_company(
    company_id: int,
    payload: SuspendIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    company = db.get(Company, company_id)
    if not company:
        raise HTTPException(404, "Empresa no encontrada")

    company.service_status = "suspended"
    company.suspended_at = datetime.now(timezone.utc)
    company.suspension_reason = payload.reason

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
        raise HTTPException(404, "Empresa no encontrada")

    company.service_status = "active"
    company.suspended_at = None
    company.suspension_reason = None

    db.commit()
    db.refresh(company)
    return company


# ==================================
# 📌 EMPLEADOS
# ==================================

class CreateEmployeeIn(BaseModel):
    company_id: int
    name: str
    email: EmailStr
    phone: str | None = None
    role: str = "collector"
    password: str


@router.post("/employees", response_model=EmployeeOut)
def admin_create_employee(
    payload: CreateEmployeeIn,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    # verificar empresa
    company = db.get(Company, payload.company_id)
    if not company:
        raise HTTPException(404, "Empresa no existe")

    # verificar email duplicado
    exists = db.query(Employee).filter(
        Employee.email.ilike(payload.email)
    ).first()
    if exists:
        raise HTTPException(400, "Ese email ya está usado")

    emp = Employee(
        name=payload.name,
        email=payload.email.lower().strip(),
        phone=payload.phone,
        role=payload.role,
        password=hash_password(payload.password),
        company_id=payload.company_id
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp


@router.get("/employees", response_model=List[EmployeeOut])
def admin_list_employees(
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    return db.query(Employee).order_by(Employee.id).all()
