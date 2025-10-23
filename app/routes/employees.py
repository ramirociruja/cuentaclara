from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from sqlalchemy import and_
from app.database.db import get_db
from app.utils.auth import hash_password, get_current_user
from app import models, schemas
from app.utils import auth
from app.schemas.employee import EmployeeCreate, EmployeeUpdate, EmployeeOut
from app.models.models import Installment, Loan, Employee
from datetime import date
from app.schemas.schemas import LoginRequest
from app.utils.license import ensure_company_active


router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)]  # 🔒
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


@router.post("/", response_model=EmployeeOut)
def create_employee(employee: EmployeeCreate, db: Session = Depends(get_db)):
    # Verificar si el email ya está registrado
    existing_employee = db.query(Employee).filter(Employee.email == employee.email).first()
    if existing_employee:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo electrónico ya está registrado."
        )
    
    # Cifrar la contraseña antes de guardarla
    hashed_password = hash_password(employee.password)
    
    # Crear un nuevo objeto Employee con el email y la contraseña cifrada
    new_employee = Employee(
        name=employee.name,
        email=employee.email,
        password=hashed_password,  # Almacenar la contraseña cifrada
        role=employee.role,
        phone=employee.phone,
        company_id=employee.company_id  # Asegúrate de que este campo se pase correctamente
    )
    
    # Añadir el nuevo empleado a la base de datos
    db.add(new_employee)
    db.commit()
    db.refresh(new_employee)
    
    return new_employee

@router.get("/", response_model=list[EmployeeOut])
def list_employees(db: Session = Depends(get_db), company_id: Optional[int] = None):
    query = db.query(Employee)
    if company_id:  # Filtrar empleados por company_id
        query = query.filter(Employee.company_id == company_id)
    return query.all()

@router.get("/{employee_id}", response_model=EmployeeOut)
def get_employee(employee_id: int, db: Session = Depends(get_db)):
    employee = db.query(Employee).get(employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    return employee

@router.put("/{employee_id}", response_model=EmployeeOut)
def update_employee(employee_id: int, update_data: EmployeeUpdate, db: Session = Depends(get_db)):
    employee = db.query(Employee).get(employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    for field, value in update_data.dict().items():
        setattr(employee, field, value)
    db.commit()
    db.refresh(employee)
    return employee

@router.delete("/{employee_id}")
def delete_employee(employee_id: int, db: Session = Depends(get_db)):
    employee = db.query(Employee).get(employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    db.delete(employee)
    db.commit()
    return {"message": "Empleado eliminado correctamente"}

@router.get("/{employee_id}/cuotas-a-cobrar")
def cuotas_a_cobrar(employee_id: int, db: Session = Depends(get_db)):
    # Verificar que exista el empleado
    employee = db.query(Employee).get(employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    # Obtener todos los préstamos asignados al empleado con al menos una cuota impaga
    loans = db.query(Loan).filter(
        and_(
            Loan.employee_id == employee_id,
            Loan.installments.any(Installment.is_paid == False)
        )
    ).all()

    cuotas_a_cobrar = []

    for loan in loans:
        # Obtener la cuota más antigua no pagada
        next_installment = (
            db.query(Installment)
            .filter(
                Installment.loan_id == loan.id,
                Installment.is_paid == False
            )
            .order_by(Installment.due_date.asc())
            .first()
        )

        if next_installment:
            cuotas_a_cobrar.append({
                "cliente": loan.customer.name,
                "prestamo_id": loan.id,
                "cuota_id": next_installment.id,
                "número_cuota": next_installment.number,
                "monto": next_installment.amount,
                "fecha_vencimiento": next_installment.due_date.strftime("%d/%m/%Y"),
                "estado": "Vencida" if next_installment.due_date < date.today() else "Pendiente",
                "pagada": "Sí" if next_installment.is_paid else "No"
            })

    return {"cuotas_a_cobrar": cuotas_a_cobrar}


@router.get("/profile")
def get_profile(current_user: models.models.Employee = Depends(auth.get_current_user)):
    return {
        "employee_id": current_user.id,
        "name": current_user.name,
        "email": current_user.email
    }