# app/jobs/overdue.py
from datetime import datetime
from zoneinfo import ZoneInfo
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.constants import InstallmentStatus
from app.database.db import SessionLocal
from app.models.models import Installment

LOCAL_TZ = ZoneInfo("America/Argentina/Tucuman")

def mark_overdue_installments(db: Session) -> int:
    """
    Marca como 'Vencida' todas las cuotas NO pagadas, cuyo due_date (fecha) ya pasó
    y que NO están Canceladas ni Refinanciadas.
    """
    today_local = datetime.now(LOCAL_TZ).date()

    # UPDATE en bloque (idempotente)
    updated = (
        db.query(Installment)
          .filter(
              Installment.is_paid == False,  # noqa: E712
              func.date(Installment.due_date) < today_local,
              Installment.status.in_([InstallmentStatus.PENDING.value,
                  InstallmentStatus.PARTIAL.value]),
          )
          .update(
              {
                  Installment.status: InstallmentStatus.OVERDUE.value,
                  Installment.is_overdue: True,
              },
              synchronize_session=False,
          )
    )
    db.commit()
    return int(updated or 0)


def mark_overdue_installments_job() -> int:
    """
    Wrapper para correr sin dependencia externa de FastAPI:
    - lo usa el scheduler (si lo habilitás)
    - o un script CLI
    """
    db = SessionLocal()
    try:
        return mark_overdue_installments(db)
    finally:
        db.close()
