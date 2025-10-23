from typing import Optional
from pydantic import BaseModel
from datetime import datetime

class CompanyBase(BaseModel):
    name: str

class CompanyCreate(CompanyBase):
    pass

class Company(CompanyBase):
    id: int
    created_at: datetime
    updated_at: datetime
    service_status: str
    license_expires_at: Optional[datetime] = None
    suspended_at: Optional[datetime] = None
    suspension_reason: Optional[str] = None

    class Config:
        orm_mode = True
