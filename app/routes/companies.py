from fastapi import HTTPException
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.database.db import SessionLocal
from app import models, schemas
from app.models.models import Company, Employee
from app.utils.auth import get_current_user
from app.schemas.companies import Company as CompanySchema

router = APIRouter(
    dependencies=[Depends(get_current_user)]  # 🔒
)
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/", response_model=list[CompanySchema])
def list_companies(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Si querés mostrar solo la empresa del usuario (recomendado):
    rows = db.query(Company).filter(Company.id == current.company_id).all()
    return rows

# routes/companies.py
@router.get("/{company_id}", response_model=CompanySchema)
def get_company(company_id: int, db: Session = Depends(get_db), current: Employee = Depends(get_current_user)):
    row = db.query(Company).filter(Company.id == company_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Company not found")
    return row
