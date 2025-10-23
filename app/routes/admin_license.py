# app/routes/admin_license.py
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database.db import get_db
from app.models.models import Company, Employee
from app.utils.auth import get_current_user

router = APIRouter()

# ---------- Auth guard: sólo superadmin / admin global ----------
def ensure_superadmin(current: Employee = Depends(get_current_user)) -> Employee:
    """
    Permite sólo cuentas con privilegios globales para operar sobre compañías.
    Ajustá la lógica según tu modelo de Employee (is_admin / role / is_superuser).
    """
    role = (getattr(current, "role", None) or "").lower()
    is_admin = bool(getattr(current, "is_admin", False) or getattr(current, "is_superuser", False))
    if not (is_admin or role in {"owner", "admin", "superadmin", "root"}):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No autorizado")
    return current

# ---------- Schemas ----------
class SuspendRequest(BaseModel):
    reason: Optional[str] = None

class ReinstateRequest(BaseModel):
    reason: Optional[str] = None  # por si querés registrar una nota de reactivación

class LicenseState(BaseModel):
    company_id: int
    service_status: str
    license_expires_at: Optional[datetime] = None
    suspended_at: Optional[datetime] = None
    suspension_reason: Optional[str] = None

class LicenseStatusOut(BaseModel):
    status: str
    license_expires_at: Optional[datetime] = None
    suspended_at: Optional[datetime] = None
    reason: Optional[str] = None

# ---------- Helpers ----------
def _get_company_or_404(db: Session, company_id: int) -> Company:
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return c

def _response_from_company(c: Company) -> LicenseState:
    return LicenseState(
        company_id=c.id,
        service_status=c.service_status,
        license_expires_at=getattr(c, "license_expires_at", None),
        suspended_at=getattr(c, "suspended_at", None),
        suspension_reason=getattr(c, "suspension_reason", None),
    )

# ---------- Endpoints ----------
@router.post("/admin/company/{company_id}/suspend", response_model=LicenseState)
def suspend_company(
    company_id: int,
    body: SuspendRequest | None = None,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    """
    Suspende el servicio para una empresa:
      - service_status = "suspended"
      - setea suspended_at y guarda motivo
    Idempotente: si ya está suspendida, responde OK con el estado actual.
    """
    c = _get_company_or_404(db, company_id)
    now = datetime.now(timezone.utc)

    if c.service_status != "suspended":
        c.service_status = "suspended"
        c.suspended_at = now
        c.suspension_reason = (body.reason.strip() if body and body.reason else None)
        db.add(c)
        db.commit()
        db.refresh(c)

    return _response_from_company(c)

@router.post("/admin/company/{company_id}/reinstate", response_model=LicenseState)
def reinstate_company(
    company_id: int,
    body: ReinstateRequest | None = None,
    db: Session = Depends(get_db),
    _: Employee = Depends(ensure_superadmin),
):
    """
    Reactiva el servicio para una empresa:
      - service_status = "active"
      - limpia suspended_at y suspension_reason
    Idempotente: si ya está activa, responde OK con el estado actual.
    Nota: no toca license_expires_at (podés manejarlo aparte).
    """
    c = _get_company_or_404(db, company_id)

    if c.service_status != "active":
        c.service_status = "active"
        c.suspended_at = None
        # opcional: conservar el historial en logs; por simplicidad, limpiamos el motivo
        c.suspension_reason = None
        db.add(c)
        db.commit()
        db.refresh(c)

    return _response_from_company(c)

@router.get("/license/validate", response_model=LicenseStatusOut)
def validate_license(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Devuelve el estado de licencia del tenant del usuario autenticado.
    No aplica ensure_company_active para permitir que el front muestre el bloqueo.
    """
    company: Company | None = db.get(Company, current.company_id)
    if not company:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Empresa no encontrada")

    return LicenseStatusOut(
        status=company.service_status,
        license_expires_at=getattr(company, "license_expires_at", None),
        suspended_at=getattr(company, "suspended_at", None),
        reason=getattr(company, "suspension_reason", None),
    )