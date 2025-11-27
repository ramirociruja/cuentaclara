# app/scripts/seed_once.py
from __future__ import annotations
import os
import logging
from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session

# ==== LOGGING ====
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(asctime)s %(message)s")
log = logging.getLogger("seed")

# Usa tus componentes existentes
from app.database.db import SessionLocal
from app.models.models import Company, Employee
from app.utils.auth import hash_password

# =========================
#       C O N S T A N T E S
# =========================
# Empresa
COMPANY_NAME = "La Fija"
COMPANY_STATUS = "active"          # "active" | "suspended" | "expired"
LICENSE_DAYS  = 30                 # días de licencia desde hoy

# Empleado ADMIN
ADMIN_NAME  = "Nadia Morales"
ADMIN_EMAIL = "nadiadmorales16@gmail.com"
ADMIN_PASS  = "123456"
ADMIN_PHONE = "3813008665"

# Empleado COBRADOR
COL_NAME  = "Agustin Diaz"
COL_EMAIL = "diazagustin2w@gmail.com"
COL_PASS  = "123456"
COL_PHONE = "3815216081"

# Empleado cobrador 2 para testing
COL2_NAME  = "Cobrador 2"
COL2_EMAIL = "cobrador2@gmail.com"
COL2_PASS  = "123456"
COL2_PHONE = "3815216082"

# =========================
#     L Ó G I C A   S E E D
# =========================

def get_session() -> Session:
    """Crea una sesión usando la config de tu proyecto (DATABASE_URL)."""
    return SessionLocal()

def get_or_create_company(db: Session) -> Company:
    comp = db.query(Company).filter(Company.name == COMPANY_NAME).first()
    if comp:
        log.info("✔ Empresa ya existe: %s (id=%s)", comp.name, comp.id)
        return comp

    license_expires_at = datetime.now(tz=timezone.utc) + timedelta(days=LICENSE_DAYS)
    comp = Company(
        name=COMPANY_NAME,
        service_status=COMPANY_STATUS,
        license_expires_at=license_expires_at,
        suspended_at=None,
        suspension_reason=None,
    )
    db.add(comp)
    db.commit()
    db.refresh(comp)
    log.info("✔ Empresa creada: %s (id=%s) — licencia hasta %s", comp.name, comp.id, comp.license_expires_at)
    return comp

def get_or_create_employee(
    db: Session,
    *,
    company: Company,
    name: str,
    email: str,
    password: str,
    role: str,
    phone: str | None = None,
) -> Employee:
    emp = db.query(Employee).filter(Employee.email == email).first()
    if emp:
        log.info("  • Empleado ya existe: %s <%s> (id=%s) role=%s", emp.name, emp.email, emp.id, emp.role)
        return emp

    emp = Employee(
        name=name,
        role=role,                # "admin" | "collector" | "supervisor"
        phone=phone,
        email=email,
        password=hash_password(password),
        company_id=company.id,
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)
    log.info("  • Empleado creado: %s <%s> (id=%s) role=%s", emp.name, emp.email, emp.id, emp.role)
    return emp

def _mask_db_url(db_url: str) -> str:
    try:
        head, tail = db_url.split("://", 1)
        creds, host = tail.split("@", 1)
        user = creds.split(":", 1)[0]
        return f"{head}://{user}:***@{host}"
    except Exception:
        return db_url

def main():
    if not os.getenv("DATABASE_URL"):
        raise SystemExit("Falta la variable de entorno DATABASE_URL (usar URL de Supabase con ?sslmode=require)")
    log.info("DATABASE_URL=%s", _mask_db_url(os.environ["DATABASE_URL"]))

    db = get_session()
    try:
        company = get_or_create_company(db)

        # Admin
        get_or_create_employee(
            db,
            company=company,
            name=ADMIN_NAME,
            email=ADMIN_EMAIL,
            password=ADMIN_PASS,
            role="admin",
            phone=ADMIN_PHONE,
        )

        # Cobrador
        get_or_create_employee(
            db,
            company=company,
            name=COL_NAME,
            email=COL_EMAIL,
            password=COL_PASS,
            role="collector",
            phone=COL_PHONE,
        )

        get_or_create_employee(
            db,
            company=company,
            name=COL2_NAME,
            email=COL2_EMAIL,
            password=COL2_PASS,
            role="collector",
            phone=COL2_PHONE,
        )

        log.info("✅ Seed de empresa + empleados finalizado.")
    finally:
        db.close()

if __name__ == "__main__":
    log.info("Ejecutando seed_once.py")
    main()
