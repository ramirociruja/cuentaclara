from __future__ import annotations

import os
import secrets
import string

from sqlalchemy.orm import Session

from app.database.db import SessionLocal
from app.models.models import Employee
from app.utils.auth import hash_password

SUPERADMIN_EMAIL = os.getenv("SUPERADMIN_EMAIL", "superadmin@cuentaclara.com").strip().lower()

# Si seteás SUPERADMIN_NEW_PASSWORD, usa esa. Si no, genera una segura.
NEW_PASSWORD_ENV = "123456"


def _generate_password(length: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits
    # Evito caracteres raros para que sea fácil de tipear/copiar
    return "".join(secrets.choice(alphabet) for _ in range(length))


def main() -> None:
    db: Session = SessionLocal()
    try:
        user = (
            db.query(Employee)
            .filter(Employee.email.ilike(SUPERADMIN_EMAIL))
            .first()
        )

        if not user:
            raise SystemExit(f"[ERROR] No existe Employee con email {SUPERADMIN_EMAIL}")

        if user.role != "superadmin":
            raise SystemExit(
                f"[ERROR] El usuario existe pero role={user.role!r}, no es 'superadmin'. Aborto por seguridad."
            )

        new_password = NEW_PASSWORD_ENV or _generate_password(16)
        user.password = hash_password(new_password)

        # Si tenés update_at/updated_at en el modelo y querés tocarlo, descomentá:
        # if hasattr(user, "updated_at"):
        #     from datetime import datetime, timezone
        #     user.updated_at = datetime.now(timezone.utc)

        db.add(user)
        db.commit()

        print("[OK] Password reseteada para superadmin.")
        print(f"      email: {user.email}")
        print(f"      new_password: {new_password}")

        if NEW_PASSWORD_ENV is None:
            print("[WARN] Se generó una password temporal. Cambiala apenas entres.")

    finally:
        db.close()


if __name__ == "__main__":
    main()
