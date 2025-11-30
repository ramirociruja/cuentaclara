# app/scripts/extend_license.py
from __future__ import annotations

import os
import logging
from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session

from app.database.db import SessionLocal
from app.models.models import Company

# ==== LOGGING ====
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(asctime)s %(message)s")
log = logging.getLogger("extend_license")

# =========================
#       C O N S T A N T E S
# =========================
TARGET_COMPANY_NAME = "Soluciones Comerciales S.A.S."  # <-- cambiala si tu hermano tiene otro nombre
EXTEND_DAYS = 30


def get_session() -> Session:
    return SessionLocal()


def _mask_db_url(db_url: str) -> str:
    try:
        head, tail = db_url.split("://", 1)
        creds, host = tail.split("@", 1)
        user = creds.split(":", 1)[0]
        return f"{head}://{user}:***@{host}"
    except Exception:
        return db_url


def main() -> None:
    if not os.getenv("DATABASE_URL"):
        raise SystemExit("Falta la variable de entorno DATABASE_URL")

    log.info("DATABASE_URL=%s", _mask_db_url(os.environ["DATABASE_URL"]))

    db = get_session()
    try:
        company = (
            db.query(Company)
            .filter(Company.name == TARGET_COMPANY_NAME)
            .first()
        )

        if not company:
            raise SystemExit(f"No se encontró la empresa '{TARGET_COMPANY_NAME}'")

        now = datetime.now(tz=timezone.utc)
        old_exp = company.license_expires_at

        # Si ya venció, arrancamos desde hoy; si no, extendemos desde la fecha actual
        base_date = old_exp or now
        if base_date < now:
            base_date = now

        new_exp = base_date + timedelta(days=EXTEND_DAYS)

        company.license_expires_at = new_exp
        company.service_status = "active"
        company.suspended_at = None
        company.suspension_reason = None

        db.commit()
        db.refresh(company)

        log.info(
            "✔ Licencia de '%s' extendida de %s a %s",
            company.name,
            old_exp,
            company.license_expires_at,
        )
    finally:
        db.close()


if __name__ == "__main__":
    log.info("Ejecutando extend_license.py")
    main()
