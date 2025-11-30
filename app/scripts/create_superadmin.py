from sqlalchemy.orm import Session
from app.database.db import SessionLocal
from app.models.models import Employee
from app.utils.auth import hash_password


SUPERADMIN_NAME = "Super Admin"
SUPERADMIN_EMAIL = "superadmin@cuentaclara.com"
SUPERADMIN_PASSWORD = "123456"
SUPERADMIN_PHONE = "0000000000"


def main() -> None:
    db: Session = SessionLocal()

    try:
        # ¿Ya existe?
        existing = (
            db.query(Employee)
            .filter(Employee.email.ilike(SUPERADMIN_EMAIL))
            .first()
        )
        if existing:
            print(f"[INFO] Ya existe un usuario con email {SUPERADMIN_EMAIL} (id={existing.id})")
            return

        hashed = hash_password(SUPERADMIN_PASSWORD)

        superadmin = Employee(
            name=SUPERADMIN_NAME,
            email=SUPERADMIN_EMAIL.lower().strip(),
            phone=SUPERADMIN_PHONE,
            role="superadmin",     # 👈 IMPORTANTE
            password=hashed,
            company_id=None,       # 👈 superadmin global (sin empresa)
        )

        db.add(superadmin)
        db.commit()
        db.refresh(superadmin)

        print(
            f"[OK] Superadmin creado con id={superadmin.id}, "
            f"email={SUPERADMIN_EMAIL}, password={SUPERADMIN_PASSWORD}"
        )

    finally:
        db.close()


if __name__ == "__main__":
    main()
