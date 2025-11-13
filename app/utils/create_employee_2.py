# scripts/create_employee.py
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from app.database.db import SessionLocal
from app.models.models import Employee

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
db: Session = SessionLocal()

hashed_password = pwd_context.hash("123456")  # Cambiá por tu contraseña

new_employee = Employee(
    name="Nadia Morales",
    role="admin",
    email="nadiadmorales16@gmail.com",
    password=hashed_password,
    company_id=4  # Usá un ID de empresa válido en tu DB
)

new_employee2 = Employee(
    name="Agustin Diaz",
    role="cobrador",
    email="Diazagustin2w@gmail.com",
    password=hashed_password,
    company_id=4  # Usá un ID de empresa válido en tu DB
)

db.add(new_employee)
db.commit()
db.refresh(new_employee)
print("Empleado creado con ID:", new_employee.id)

db.add(new_employee2)
db.commit()
db.refresh(new_employee2)
print("Empleado creado con ID:", new_employee2.id)
