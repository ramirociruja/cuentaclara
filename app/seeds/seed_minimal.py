# app/seeds/seed_minimal.py
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database.db import Base
from app.models.models import Company, Employee
# Si tu login usa hashing/bcrypt, dejá este import:
from app.utils.auth import hash_password

DATABASE_URL = os.environ["DATABASE_URL"]  # usa la conexión DIRECTA (5432) de Supabase
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

def ensure_seed():
    db = SessionLocal()
    try:
        # Si tus tablas ya están migradas con Alembic, no hace falta create_all
        # Base.metadata.create_all(engine)

        # Evitar duplicados si re-ejecutás
        company = db.query(Company).first()
        if not company:
            company = Company(name="CuentaClara")
            db.add(company)
            db.flush()

        existing_admin = db.query(Employee).filter(Employee.email == "admin@example.com").first()
        if existing_admin:
            print("Admin ya existe; seed omitido.")
            return

        # Si tu auth guarda HASH en employee.password:
        admin_password_plain = "secret123"
        admin_password_hashed = hash_password(admin_password_plain)

        admin = Employee(
            name="Admin",
            email="admin@example.com",
            role="admin",             # <-- requerido por tu modelo
            password=admin_password_hashed,  # <-- campo correcto en tu modelo
            company_id=company.id,
            # token_version usa default 0
        )
        db.add(admin)
        db.commit()

        print("Seed OK ✅")
        print(f"- Company: {company.name} (id={company.id})")
        print(f"- Admin:   admin@example.com / {admin_password_plain}")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

if __name__ == "__main__":
    ensure_seed()
