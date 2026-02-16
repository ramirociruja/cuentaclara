from pydantic import BaseModel, EmailStr, Field
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

    # ✅ nuevos
    is_active: bool
    disabled_at: Optional[datetime] = None
    last_login_at: Optional[datetime] = None

    class Config:
        from_attributes = True  # ✅ pydantic v2 (reemplaza orm_mode)

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



class EmployeePasswordUpdate(BaseModel):
    password: str = Field(..., min_length=6, max_length=128)

class EmployeeMyPasswordUpdate(BaseModel):
    current_password: str = Field(..., min_length=6, max_length=128)
    new_password: str = Field(..., min_length=6, max_length=128)