# app/routes/tasks.py
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from datetime import datetime
from zoneinfo import ZoneInfo

from app.database.db import get_db
from app.utils.auth import get_current_user
from app.models.models import Employee
from app.jobs.overdue import mark_overdue_installments

router = APIRouter(prefix="/tasks", tags=["Tasks"])
LOCAL_TZ = ZoneInfo("America/Argentina/Tucuman")

@router.post("/mark-overdue", status_code=status.HTTP_200_OK)
def run_mark_overdue(
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Ejecuta el marcaje de cuotas vencidas.
    Requiere estar autenticado.
    """
    updated = mark_overdue_installments(db)
    return {
        "updated": updated,
        "ran_at": datetime.now(LOCAL_TZ).isoformat(),
    }
