from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime

class CustomerBase(BaseModel):
    name: str
    dni: Optional[str] = Field(None, min_length=7)
    address: str
    phone: str
    email: str  # Nuevo campo de correo electrónico
    province: Optional[str] = None
    company_id: int
    employee_id: int

    @field_validator('dni')
    @classmethod
    def dni_must_be_valid(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.isalnum():
            raise ValueError('DNI debe contener solo caracteres alfanuméricos')
        return v.upper() if v is not None else v

    @field_validator('email')
    @classmethod
    def email_must_be_valid(cls, v: str) -> str:
        if '@' not in v or '.' not in v:
            raise ValueError('Correo electrónico no es válido')
        return v

class CustomerCreate(CustomerBase):
    pass

class CustomerOut(CustomerBase):
    id: int
    created_at: Optional[datetime] = None  # Cambiado a Optional
    
    class Config:
        from_attributes = True  # Equivalente a orm_mode=True en Pydantic v2
