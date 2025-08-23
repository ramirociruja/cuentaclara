from app.database.db import SessionLocal
from app.models.models import Company
from datetime import datetime

db = SessionLocal()

# Crear la empresa
new_company = Company(
    name="Cuenta Clara S.R.L.",
    created_at=datetime.utcnow(),
    updated_at=datetime.utcnow()
)

db.add(new_company)
db.commit()
db.refresh(new_company)

print(f"Empresa creada con ID: {new_company.id}")
