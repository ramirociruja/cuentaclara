import time
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.database.db import SessionLocal  # ajusta si tu import es distinto

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

router = APIRouter(prefix="/debug", tags=["debug"])

@router.get("/ping_db")
def ping_db(db: Session = Depends(get_db)):
    """
    Mide el tiempo real que tarda un SELECT 1 contra la DB.
    """
    start = time.perf_counter()

    db.execute(text("SELECT 1"))

    end = time.perf_counter()

    elapsed_ms = round((end - start) * 1000, 2)

    return {
        "status": "ok",
        "db_latency_ms": elapsed_ms
    }