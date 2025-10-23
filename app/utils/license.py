# app/utils/license.py
from fastapi import HTTPException, status, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timezone

from app.database.db import get_db
from app.models.models import Company, Employee
from app.utils.auth import get_current_user

def ensure_company_active(
    current: Employee = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    company = db.query(Company).get(current.company_id)
    if not company:
        raise HTTPException(status_code=403, detail="Empresa no encontrada")

    # Expiración automática
    if company.license_expires_at and company.license_expires_at < datetime.now(timezone.utc):
        if company.service_status != "expired":
            company.service_status = "expired"
            db.add(company)
            db.commit()

    if company.service_status in {"suspended", "expired"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "SERVICE_SUSPENDED", "status": company.service_status, "reason": company.suspension_reason}
        )
    return True
