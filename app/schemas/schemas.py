from pydantic import BaseModel

# Esquema para la solicitud de login
class LoginRequest(BaseModel):
    username: str  # Este es el email
    password: str   # La contraseña del empleado


class RefreshRequest(BaseModel):
    refresh_token: str

class TokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    employee_id: int
    company_id: int
    name: str
    email: str
