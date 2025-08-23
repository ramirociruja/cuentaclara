from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.database.db import SessionLocal
from app import models, schemas

router = APIRouter()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.get("/companies", response_model=schemas.Company)
def get_companies(db: Session = Depends(get_db)):
    return db.query(models.Company).all()
