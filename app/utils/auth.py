# app/utils/auth.py
from datetime import datetime, timedelta, timezone
from typing import Optional
from sqlalchemy import func

from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.database.db import get_db
from app.models import models
from app.schemas.schemas import LoginRequest, RefreshRequest, TokenPairResponse
from app.config import (
    SECRET_KEY,
    JWT_ALGORITHM,
    JWT_EXPIRE_MINUTES,
    JWT_REFRESH_EXPIRE_MINUTES,
)

router = APIRouter(tags=["auth"])
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ===== Password hashing =====
def hash_password(plain_password: str) -> str:
    return pwd_context.hash(plain_password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

# ===== OAuth2 / JWT =====
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

def _jwt_encode(payload: dict, minutes: int) -> str:
    exp = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    to_encode = payload.copy()
    to_encode.update({"exp": exp})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=JWT_ALGORITHM)

def create_access_token(employee: models.Employee) -> str:
    # Incluye token_version (tv) para invalidar access tokens en logout_all
    return _jwt_encode(
        {
            "sub": str(employee.id),
            "company_id": employee.company_id,
            "scope": "access",
            "tv": int(getattr(employee, "token_version", 0)),
        },
        JWT_EXPIRE_MINUTES,
    )

def create_refresh_token(employee: models.Employee) -> str:
    # El refresh ya usaba tv para rotación segura
    return _jwt_encode(
        {
            "sub": str(employee.id),
            "company_id": employee.company_id,
            "scope": "refresh",
            "tv": int(getattr(employee, "token_version", 0)),
        },
        JWT_REFRESH_EXPIRE_MINUTES,
    )

def decode_token(token: str) -> dict:
    return jwt.decode(token, SECRET_KEY, algorithms=[JWT_ALGORITHM])

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.Employee:
    cred_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No autorizado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
        if payload.get("scope") != "access":
            raise cred_exc
        sub = payload.get("sub")
        tv_in_token = payload.get("tv")  # obligatorio para invalidación instantánea
        if sub is None or tv_in_token is None:
            raise cred_exc
        employee_id = int(sub)
        tv_in_token = int(tv_in_token)
    except (JWTError, ValueError):
        raise cred_exc

    employee = db.query(models.Employee).filter(models.Employee.id == employee_id).first()
    if not employee:
        raise cred_exc

    # Comparar versión de token (tv) con la actual en DB
    current_tv = int(getattr(employee, "token_version", 0))
    if tv_in_token != current_tv:
        # access token viejo/invalidado
        raise cred_exc

    return employee

# ===== Endpoints =====

@router.post("/login", response_model=TokenPairResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    # Normalizar email recibido
    normalized_email = request.username.strip().lower()

    # Buscar ignorando mayúsculas/minúsculas
    employee = (
        db.query(models.Employee)
        .filter(func.lower(models.Employee.email) == normalized_email)
        .first()
    )

    if not employee:
        raise HTTPException(status_code=401, detail="Email o contraseña incorrecta")

    stored_hash = employee.password
    if not verify_password(request.password, stored_hash):
        raise HTTPException(status_code=401, detail="Email o contraseña incorrecta")

    access = create_access_token(employee)
    refresh = create_refresh_token(employee)
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "employee_id": employee.id,
        "company_id": employee.company_id,
        "name": employee.name,
        "email": employee.email,
    }


@router.post("/refresh", response_model=TokenPairResponse)
def refresh_token(body: RefreshRequest, db: Session = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token)
    except JWTError:
        raise HTTPException(status_code=401, detail="Refresh token inválido")

    if payload.get("scope") != "refresh":
        raise HTTPException(status_code=401, detail="Token inválido (scope)")

    sub = payload.get("sub")
    tv = payload.get("tv")
    if sub is None or tv is None:
        raise HTTPException(status_code=401, detail="Token inválido (claims)")

    try:
        employee_id = int(sub)
        token_version_in_token = int(tv)
    except ValueError:
        raise HTTPException(status_code=401, detail="Token inválido (formato)")

    employee = db.query(models.Employee).filter(models.Employee.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=401, detail="Usuario no encontrado")

    current_version = int(getattr(employee, "token_version", 0))
    if token_version_in_token != current_version:
        raise HTTPException(status_code=401, detail="Refresh token caducado o rotado")

    # Rotación: invalida refresh previos incrementando la versión
    employee.token_version = current_version + 1
    db.add(employee)
    db.commit()
    db.refresh(employee)

    access = create_access_token(employee)
    refresh = create_refresh_token(employee)

    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "employee_id": employee.id,
        "company_id": employee.company_id,
        "name": employee.name,
        "email": employee.email,
    }

@router.post("/logout_all", status_code=204)
def logout_all(db: Session = Depends(get_db), current: models.Employee = Depends(get_current_user)):
    """
    Invalida TODOS los refresh tokens y access tokens del usuario actual
    elevando la 'token_version'. Todo token emitido con una versión anterior
    queda inválido de inmediato.
    """
    current.token_version = int(getattr(current, "token_version", 0)) + 1
    db.add(current)
    db.commit()
    return
