from passlib.context import CryptContext
from datetime import datetime, timedelta
from jose import JWTError, jwt
from typing import Union
from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from app.models import models
from app.database.db import get_db
from app.schemas.schemas import LoginRequest

router = APIRouter()

# Seguridad con OAuth2
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

# Configuración para cifrar contraseñas
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Clave secreta para JWT
SECRET_KEY = "your_secret_key"  # Cambiar por una clave segura real
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30


# =========================
# AUTH UTILITIES
# =========================

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: Union[timedelta, None] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# =========================
# LOGIN ENDPOINT
# =========================

@router.post("/login")
async def login(request: LoginRequest, db: Session = Depends(get_db)):
    employee = db.query(models.Employee).filter(models.Employee.email == request.username).first()

    if not employee or not verify_password(request.password, employee.password):
        raise HTTPException(status_code=401, detail="Email o contraseña incorrecta")

    access_token = create_access_token(data={"sub": str(employee.id)})
    
    # Agregar employee_id y company_id a la respuesta
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "employee_id": employee.id,  # Agregado el ID del empleado
        "company_id": employee.company_id  # Agregado el ID de la empresa
    }


# =========================
# OBTENER USUARIO AUTENTICADO
# =========================

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> models.Employee:
    credentials_exception = HTTPException(status_code=401, detail="No se pudo validar el token")

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        employee_id: str = payload.get("sub")
        if employee_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    employee = db.query(models.Employee).filter(models.Employee.id == int(employee_id)).first()
    if employee is None:
        raise credentials_exception
    return employee
