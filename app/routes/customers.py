import re
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from typing import List, Optional
from app.database.db import SessionLocal
from app.models.models import Customer
from app.schemas.customers import CustomerCreate, CustomerOut
from app.models.models import Company  # Asegúrate de importar el modelo Company
from sqlalchemy.ext.asyncio import AsyncSession  # Importación correcta
from sqlalchemy.future import select
from datetime import datetime
from fastapi import status

router = APIRouter()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def normalize_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    digits = re.sub(r"\D", "", phone)
    # Opcional: reglas locales AR
    if digits.startswith("0"):
        digits = digits[1:]
    if digits.startswith("54") and len(digits) > 10:
        digits = digits[2:]
    return digits

@router.post("/", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(customer: CustomerCreate, db: Session = Depends(get_db)):
    """
    Crea un cliente nuevo. Si DNI o teléfono ya existen (según la política),
    devuelve 409 Conflict con un mensaje claro.
    """
    # Normalizamos el teléfono para evitar duplicados por formato
    phone_norm = normalize_phone(customer.phone)
    # Construimos los datos a insertar
    data = customer.model_dump(exclude_unset=True)
    data.pop("created_at", None)
    data["phone"] = phone_norm

    # --- Política de unicidad ---
    # Si tu negocio es multi-empresa, validamos dentro de company_id.
    # Si NO lo es, quitá el filtro por company_id en los pre-chequeos de abajo.
    company_filter = (
        (Customer.company_id == data["company_id"])
        if "company_id" in data and data["company_id"] is not None
        else True  # no filtra por empresa
    )

    # --- Pre-chequeo explícito para mejor mensaje de error ---
    duplicates = db.query(Customer).filter(
        company_filter,
        or_(
            Customer.dni == data.get("dni"),
            Customer.phone == phone_norm if phone_norm else False
        )
    ).all()

    dup_dni = any(c.dni == data.get("dni") and data.get("dni") is not None for c in duplicates)
    dup_phone = any(c.phone == phone_norm and phone_norm is not None for c in duplicates)

    if dup_dni and dup_phone:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="DNI y teléfono ya están registrados."
        )
    if dup_dni:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="DNI ya registrado."
        )
    if dup_phone:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Teléfono ya registrado."
        )

    # --- Insert ---
    new_customer = Customer(**data)
    db.add(new_customer)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        # Fallback por si hay condición de carrera: mapeamos el constraint a un mensaje claro
        # Intentamos leer el nombre de la constraint (Postgres lo expone en e.orig.diag.constraint_name)
        constraint = getattr(getattr(e, "orig", None), "diag", None)
        constraint_name = getattr(constraint, "constraint_name", "") if constraint else ""

        # Ajustá estos nombres a tus constraints reales:
        #   - customers_dni_key (UNIQUE(dni))
        #   - customers_phone_key (UNIQUE(phone))
        #   - customers_company_dni_key (UNIQUE(company_id, dni))
        #   - customers_company_phone_key (UNIQUE(company_id, phone))
        if "dni" in constraint_name:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="DNI ya registrado."
            )
        if "phone" in constraint_name:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Teléfono ya registrado."
            )
        # Si no pudimos identificar, damos un mensaje genérico pero útil
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya existe un cliente con los mismos datos únicos (DNI o teléfono)."
        )

    db.refresh(new_customer)
    return new_customer

# Obtener customer - USADO
@router.get("/{customer_id}", response_model=CustomerOut)
def get_customer(customer_id: int, db: Session = Depends(get_db)):
    customer = db.query(Customer).filter(Customer.id == customer_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer not found")
    return customer


@router.put("/{customer_id}", response_model=CustomerOut)
def update_customer(customer_id: int, customer: CustomerCreate, db: Session = Depends(get_db)):
    # Buscar el cliente en la base de datos
    db_customer = db.query(Customer).filter(Customer.id == customer_id).first()
    if not db_customer:
        # Si el cliente no existe, devolver un error 404
        raise HTTPException(status_code=404, detail="Customer not found")

    # Actualizar los campos del cliente solo si los datos han sido proporcionados
    for key, value in customer.model_dump(exclude_unset=True).items():
        setattr(db_customer, key, value)  # Asignar el valor actualizado

    # Guardar los cambios en la base de datos
    db.commit()
    db.refresh(db_customer)  # Obtener los datos actualizados

    return db_customer  # Devolver el cliente actualizado

@router.get("/", response_model=List[CustomerOut])
def get_customers(db: Session = Depends(get_db), company_id: Optional[int] = None):
    query = db.query(Customer)
    if company_id:  # Si se pasa company_id, filtramos por él
        query = query.filter(Customer.company_id == company_id)
    return query.all()



@router.get("/employees/{employee_id}", response_model=List[CustomerOut])
def get_customers_by_employee(employee_id: int, db: Session = Depends(get_db)):
    customers = db.query(Customer).filter(Customer.employee_id == employee_id).all()
    if not customers:
        raise HTTPException(status_code=404, detail="No customers found for this employee")
    return customers
