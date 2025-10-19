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

router = APIRouter(
    dependencies=[Depends(get_current_user)],  # exige Bearer válido
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
    # Opcional: limpieza típica AR
    if digits.startswith("0"):
        digits = digits[1:]
    if digits.startswith("54") and len(digits) > 10:
        digits = digits[2:]
    return digits

def _404():
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recurso no encontrado")

# ===========================
#        CREATE
# ===========================
@router.post("/", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(
    payload: CustomerCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Forzar scope por empresa desde el token
    phone_norm = normalize_phone(payload.phone)
    data = payload.model_dump(exclude_unset=True)
    data.pop("created_at", None)
    data["phone"] = phone_norm
    data["company_id"] = current.company_id  # 👈 ignoramos company_id del body

    # Pre-chequeo de duplicados dentro de la empresa
    qdup = db.query(Customer).filter(Customer.company_id == current.company_id)
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
            # Señales finas
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups) and \
               any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI y teléfono ya están registrados en esta empresa.")
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI ya registrado en esta empresa.")
            if any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="Teléfono ya registrado en esta empresa.")
            if any(c.email == data.get("email") and data.get("email") is not None for c in dups):
                raise HTTPException(status_code=409, detail="Email ya registrado en esta empresa.")

    obj = Customer(**data)
    db.add(obj)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        # Mapear nombres de constraints (cubriendo los que ya creamos y variantes antiguas)
        constraint = getattr(getattr(e, "orig", None), "diag", None)
        cname = getattr(constraint, "constraint_name", "") if constraint else ""
        if cname in {"uq_customer_company_dni", "customers_company_dni_key", "customers_dni_key"}:
            raise HTTPException(status_code=409, detail="DNI ya registrado en esta empresa.")
        if cname in {"uq_customer_company_phone", "customers_company_phone_key", "customers_phone_key"}:
            raise HTTPException(status_code=409, detail="Teléfono ya registrado en esta empresa.")
        if cname in {"uq_customer_company_email", "customers_company_email_key", "customers_email_key"}:
            raise HTTPException(status_code=409, detail="Email ya registrado en esta empresa.")
        raise HTTPException(status_code=409, detail="Ya existe un cliente con DNI/telefono/email en esta empresa.")
    db.refresh(obj)
    return obj

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

    # Validar duplicados solo si cambian esos campos
    def _exists(field: str, value: Optional[str]) -> bool:
        if not value:
            return False
        return db.query(Customer).filter(
            Customer.company_id == current.company_id,
            getattr(Customer, field) == value,
            Customer.id != customer_id,
        ).first() is not None

    if "dni" in changes and changes["dni"] != obj.dni and _exists("dni", changes["dni"]):
        raise HTTPException(status_code=409, detail="DNI ya registrado en esta empresa.")
    if "phone" in changes and changes["phone"] != obj.phone and _exists("phone", changes["phone"]):
        raise HTTPException(status_code=409, detail="Teléfono ya registrado en esta empresa.")
    if "email" in changes and changes["email"] != obj.email and _exists("email", changes["email"]):
        raise HTTPException(status_code=409, detail="Email ya registrado en esta empresa.")

    # Aplicar cambios permitidos
    for k, v in changes.items():
        setattr(obj, k, v)

    # company_id SIEMPRE el del token (ignoramos si vino en body)
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
    # 200 con [] si no hay resultados (más friendly para el front)
    return db.query(Customer).filter(
        Customer.company_id == current.company_id,
        Customer.employee_id == employee_id
    ).order_by(Customer.name.asc()).all()
