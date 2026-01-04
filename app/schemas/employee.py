from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class EmployeeBase(BaseModel):
    name: str
    role: str
    phone: Optional[str] = None
    company_id: int  # Añadimos `company_id`
    email: EmailStr  # Añadimos el campo `email` con validación de correo

class EmployeeCreate(EmployeeBase):
    password: str  # Añadimos el campo `password` para la creación

class EmployeeUpdate(BaseModel):
    name: Optional[str] = None
    role: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[EmailStr] = None  # Permitimos que el email sea opcional en las actualizaciones

class EmployeeOut(EmployeeBase):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True

class EmployeeCreateIn(BaseModel):
    name: str
    email: EmailStr
    role: str  # "admin" | "collector" | etc
    phone: str | None = None
    company_id: int
    password: str


class EmployeeUpdateIn(BaseModel):
    name: str | None = None
    email: EmailStr | None = None
    role: str | None = None
    phone: str | None = None
    company_id: int | None = None


class EmployeePasswordResetIn(BaseModel):
    new_password: str
