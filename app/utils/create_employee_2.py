# scripts/create_employee.py
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from app.database.db import SessionLocal
from app.models.models import Employee

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
db: Session = SessionLocal()

hashed_password = pwd_context.hash("123456")  # Cambiá por tu contraseña

new_employee = Employee(
    name="Admin",
    role="admin",
    email="admin3@example.com",
    password=hashed_password,
    company_id=1  # Usá un ID de empresa válido en tu DB
)

db.add(new_employee)
db.commit()
db.refresh(new_employee)
print("Empleado creado con ID:", new_employee.id)
