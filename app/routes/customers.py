from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
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

# Creacion de un nuevo customer - USADO
@router.post("/", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(customer: CustomerCreate, db: Session = Depends(get_db)):
    if db.query(Customer).filter(Customer.dni == customer.dni).first():
        raise HTTPException(status_code=400, detail="DNI ya registrado")

    data = customer.model_dump(exclude_unset=True)
    data.pop("created_at", None)

    new_customer = Customer(**data)
    db.add(new_customer)
    db.commit()
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
