import re
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, and_
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.database.db import SessionLocal
from app.models.models import Customer, Employee
from app.schemas.customers import CustomerCreate, CustomerUpdate, CustomerOut
from app.utils.auth import get_current_user
from app.utils.license import ensure_company_active

router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],
)

# --- DB session helper ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Utils ---
def normalize_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    digits = re.sub(r"\D", "", phone)
    if digits.startswith("0"):
        digits = digits[1:]
    if digits.startswith("54") and len(digits) > 10:
        digits = digits[2:]
    return digits

def _404():
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recurso no encontrado")

def _is_admin_or_manager(emp: Employee) -> bool:
    # Ajustá según tus roles reales
    return emp.role in {"admin", "manager", "ADMIN", "MANAGER"}

# ===========================
#        CREATE
# ===========================
@router.post("/", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(
    payload: CustomerCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    phone_norm = normalize_phone(payload.phone)
    data = payload.model_dump(exclude_unset=True)
    data.pop("created_at", None)
    data["phone"] = phone_norm

    # Forzar scope por empresa desde el token
    data["company_id"] = current.company_id

    # Determinar el owner empleado (unicidad por empleado)
    owner_employee_id: int
    if _is_admin_or_manager(current):
        # Admin/manager puede crear para otro empleado si viene en el body
        owner_employee_id = int(data.get("employee_id") or current.id)
    else:
        # Cobrador: siempre él mismo
        owner_employee_id = current.id
    data["employee_id"] = owner_employee_id  # asegurar consistencia

    # Pre-chequeo de duplicados dentro del EMPLEADO (no por empresa)
    qdup = db.query(Customer).filter(
        Customer.employee_id == owner_employee_id
    )
    or_terms = []
    if data.get("dni"):
        or_terms.append(Customer.dni == data["dni"])
    if phone_norm:
        or_terms.append(Customer.phone == phone_norm)
    if data.get("email"):
        or_terms.append(Customer.email == data["email"])
    if or_terms:
        dups = qdup.filter(or_(*or_terms)).all()
        if dups:
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups) and \
               any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI y teléfono ya están registrados para este empleado.")
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI ya registrado para este empleado.")
            if any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="Teléfono ya registrado para este empleado.")
            if any(c.email == data.get("email") and data.get("email") is not None for c in dups):
                raise HTTPException(status_code=409, detail="Email ya registrado para este empleado.")

    obj = Customer(**data)
    db.add(obj)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        # Mapear nombres de constraints por empleado
        constraint = getattr(getattr(e, "orig", None), "diag", None)
        cname = getattr(constraint, "constraint_name", "") if constraint else ""

        # Nuevos únicos por empleado
        if cname in {"ux_customers_employee_dni"}:
            raise HTTPException(status_code=409, detail="DNI ya registrado para este empleado.")
        if cname in {"ux_customers_employee_phone"}:
            raise HTTPException(status_code=409, detail="Teléfono ya registrado para este empleado.")
        if cname in {"ux_customers_employee_email"}:
            raise HTTPException(status_code=409, detail="Email ya registrado para este empleado.")

        # Compatibilidad hacia atrás (por si existe algún resto de constraints viejas)
        if cname in {"uq_customer_company_dni", "customers_company_dni_key", "customers_dni_key"}:
            raise HTTPException(status_code=409, detail="DNI ya registrado.")
        if cname in {"uq_customer_company_phone", "customers_company_phone_key", "customers_phone_key"}:
            raise HTTPException(status_code=409, detail="Teléfono ya registrado.")
        if cname in {"uq_customer_company_email", "customers_company_email_key", "customers_email_key"}:
            raise HTTPException(status_code=409, detail="Email ya registrado.")

        raise HTTPException(status_code=409, detail="Ya existe un cliente con DNI/teléfono/email para este empleado.")
    db.refresh(obj)
    return obj


@router.get("/", response_model=List[CustomerOut])
def list_company_customers(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Lista TODOS los clientes de la empresa del usuario logueado,
    ordenados por apellido y nombre.
    """
    return (
        db.query(Customer)
        .filter(Customer.company_id == current.company_id)
        .order_by(Customer.last_name.asc(), Customer.first_name.asc())
        .all()
    )


# ===========================
#        GET BY ID
# ===========================
@router.get("/{customer_id}", response_model=CustomerOut)
def get_customer(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    obj = db.query(Customer).filter(Customer.id == customer_id).first()
    # Seguridad por empresa
    if not obj or obj.company_id != current.company_id:
        _404()
    return obj

# ===========================
#        UPDATE
# ===========================
@router.put("/{customer_id}", response_model=CustomerOut)
def update_customer(
    customer_id: int,
    payload: CustomerUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    obj = db.query(Customer).filter(Customer.id == customer_id).first()
    if not obj or obj.company_id != current.company_id:
        _404()

    changes = payload.model_dump(exclude_unset=True)

    # Normalizar phone si vino
    if "phone" in changes and changes["phone"] is not None:
        changes["phone"] = normalize_phone(changes["phone"])

    # Determinar employee destino para validación de unicidad.
    # - Si sos admin/manager y el payload trae employee_id, validamos contra ese destino.
    # - Si no, se valida contra el employee actual del registro.
    target_employee_id = obj.employee_id
    if _is_admin_or_manager(current) and "employee_id" in changes and changes["employee_id"]:
        target_employee_id = int(changes["employee_id"])

    # Validar duplicados por empleado destino SOLO si cambian esos campos o si cambia employee_id
    def _exists(field: str, value: Optional[str]) -> bool:
        if not value:
            return False
        return db.query(Customer).filter(
            Customer.employee_id == target_employee_id,
            getattr(Customer, field) == value,
            Customer.id != customer_id,
        ).first() is not None

    if "dni" in changes and changes["dni"] != obj.dni and _exists("dni", changes["dni"]):
        raise HTTPException(status_code=409, detail="DNI ya registrado para ese empleado.")
    if "phone" in changes and changes["phone"] != obj.phone and _exists("phone", changes["phone"]):
        raise HTTPException(status_code=409, detail="Teléfono ya registrado para ese empleado.")
    if "email" in changes and changes["email"] != obj.email and _exists("email", changes["email"]):
        raise HTTPException(status_code=409, detail="Email ya registrado para ese empleado.")

    # Si solo cambia employee_id (y no cambió dni/phone/email) igual hay que validar que
    # en el destino no exista un registro con mismos datos.
    if ("employee_id" in changes and int(changes["employee_id"]) != obj.employee_id):
        for fld in ("dni", "phone", "email"):
            val = changes.get(fld, getattr(obj, fld))
            if val and _exists(fld, val):
                raise HTTPException(status_code=409, detail=f"{fld.upper()} ya registrado para ese empleado.")

    # Aplicar cambios permitidos
    for k, v in changes.items():
        setattr(obj, k, v)

    # company_id SIEMPRE el del token
    obj.company_id = current.company_id

    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


# ===========================
#      BY EMPLOYEE (scope)
# ===========================
@router.get("/employees/{employee_id}", response_model=List[CustomerOut])
def get_customers_by_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Asegurar que el employee pertenece a la misma empresa
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp or emp.company_id != current.company_id:
        _404()

    return (
        db.query(Customer)
        .filter(Customer.company_id == current.company_id)
        .order_by(Customer.last_name.asc(), Customer.first_name.asc())
        .all()
    )
