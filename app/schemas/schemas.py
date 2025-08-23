from pydantic import BaseModel

# Esquema para la solicitud de login
class LoginRequest(BaseModel):
    username: str  # Este es el email
    password: str   # La contraseña del empleado
