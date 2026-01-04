# app/scripts/create_superadmin_dev.py

from datetime import datetime, UTC
from sqlalchemy.orm import Session
from passlib.context import CryptContext

from app.database.db import SessionLocal
from app.models.models import Company, Employee

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

SUPERADMIN_COMPANY_NAME = "SuperAdmin Global"
SUPERADMIN_NAME = "Super Admin"
SUPERADMIN_EMAIL = "superadmin@dev.com"
SUPERADMIN_PASSWORD = "123456"

def main():
    db: Session = SessionLocal()

    # 1) Crear empresa superadmin
    company = Company(
        name=SUPERADMIN_COMPANY_NAME,
        service_status="active",
        license_expires_at=None
    )
    db.add(company)
    db.commit()
    db.refresh(company)

    print(f"Empresa SuperAdmin creada con ID: {company.id}")

    # 2) Crear superadmin
    hashed_password = pwd_context.hash(SUPERADMIN_PASSWORD)

    superadmin = Employee(
        name=SUPERADMIN_NAME,
        email=SUPERADMIN_EMAIL,
        password=hashed_password,
        role="superadmin",
        phone=None,
        company_id=company.id,    # 👈 lo vinculamos
        created_at=datetime.now(UTC),
    )

    db.add(superadmin)
    db.commit()
    db.refresh(superadmin)

    print("\n===== SUPERADMIN CREADO =====")
    print(f"ID: {superadmin.id}")
    print(f"Email: {SUPERADMIN_EMAIL}")
    print(f"Password: {SUPERADMIN_PASSWORD}")
    print("=============================")


if __name__ == "__main__":
    main()
