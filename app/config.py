# backend/app/config.py
import os
from dotenv import load_dotenv

load_dotenv()

ENV = os.getenv("ENV", "dev").lower()

SECRET_KEY = os.getenv("SECRET_KEY")
if ENV == "prod":
    # En prod: clave obligatoria y suficientemente larga (>=32 bytes)
    if not SECRET_KEY or len(SECRET_KEY) < 32:
        raise RuntimeError("SECRET_KEY requerido en prod (>=32 bytes)")

# JWT
JWT_ALGORITHM = os.getenv("JWT_ALGO", "HS256")
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_MINS", "60"))
JWT_REFRESH_EXPIRE_MINUTES = int(os.getenv("JWT_REFRESH_MINS", "10080"))
