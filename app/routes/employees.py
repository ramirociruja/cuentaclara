from locale import currency
from typing import Optional
from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from app.database.db import get_db
from app.schemas import employee
from app.utils.auth import hash_password, get_current_user
from app import models, schemas
from app.utils import auth
from app.schemas.employee import EmployeeCreate, EmployeeMyPasswordUpdate, EmployeePasswordUpdate, EmployeeUpdate, EmployeeOut
from app.models.models import Installment, Loan, Employee
from datetime import date, datetime, timezone
from app.schemas.schemas import LoginRequest
from app.utils.license import ensure_company_active
from app.utils.auth import hash_password, verify_password  # verify_password si existe



router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)]  # 🔒
)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


def ensure_admin(current: Employee):
    if (current.role or "").lower() not in ("admin", "manager"):  # ajustá roles
        raise HTTPException(status_code=403, detail="No autorizado")

@router.put("/{employee_id}/password", status_code=204)
def admin_set_employee_password(
    employee_id: int,
    payload: EmployeePasswordUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ensure_admin(current)

    employee = db.get(Employee, employee_id)
    if not employee or employee.company_id != current.company_id:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    employee.password = hash_password(payload.password)

    # opcional recomendado: invalidar sesiones activas
    employee.token_version = (employee.token_version or 0) + 1

    db.commit()
    return

@router.put("/me/password", status_code=204)
def change_my_password(
    payload: EmployeeMyPasswordUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # si no tenés verify_password, lo agregamos en utils/auth
    if not verify_password(payload.current_password, current.password):
        raise HTTPException(status_code=400, detail="Contraseña actual incorrecta")

    current.password = hash_password(payload.new_password)
    current.token_version = (current.token_version or 0) + 1
    db.commit()
    return


@router.post("/{employee_id}/disable", status_code=204)
def disable_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ensure_admin(current)
    emp = db.get(Employee, employee_id)
    if not emp or emp.company_id != current.company_id:
        raise HTTPException(404, "Empleado no encontrado")
    emp.is_active = False
    emp.disabled_at = datetime.now(timezone.utc)
    emp.token_version = (emp.token_version or 0) + 1
    db.commit()
    return

@router.post("/{employee_id}/enable", status_code=204)
def enable_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    ensure_admin(current)
    emp = db.get(Employee, employee_id)
    if not emp or emp.company_id != current.company_id:
        raise HTTPException(404, "Empleado no encontrado")
    emp.is_active = True
    emp.disabled_at = None
    db.commit()
    return



@router.post("/", response_model=EmployeeOut)
def create_employee(employee: EmployeeCreate, db: Session = Depends(get_db)):
    normalized_email = employee.email.strip().lower()

    # Verificar si el email ya está registrado (case-insensitive)
    existing_employee = (
        db.query(Employee)
        .filter(func.lower(Employee.email) == normalized_email)
        .first()
    )
    if existing_employee:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo electrónico ya está registrado."
        )

    hashed_password = hash_password(employee.password)

    new_employee = Employee(
        name=employee.name,
        role=employee.role,
        phone=employee.phone,
        email=normalized_email,  # 👈 guardamos en minúsculas
        password=hashed_password,
        company_id=employee.company_id,
    )

    db.add(new_employee)
    db.commit()
    db.refresh(new_employee)
    return new_employee


@router.get("/", response_model=list[EmployeeOut])
def list_employees(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Lista empleados SOLO de la empresa del usuario logueado.
    Ignoramos company_id para no romper el aislamiento entre empresas.
    """
    query = (
        db.query(Employee)
        .filter(Employee.company_id == current.company_id)
        .order_by(Employee.name.asc())
    )
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

    # Si viene email nuevo, normalizar y chequear duplicados
    if update_data.email is not None:
        normalized_email = update_data.email.strip().lower()

        existing = (
            db.query(Employee)
            .filter(Employee.id != employee_id)
            .filter(func.lower(Employee.email) == normalized_email)
            .first()
        )
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El correo electrónico ya está registrado."
            )

        employee.email = normalized_email

    if update_data.name is not None:
        employee.name = update_data.name
    if update_data.role is not None:
        employee.role = update_data.role
    if update_data.phone is not None:
        employee.phone = update_data.phone

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