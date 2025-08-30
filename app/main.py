from fastapi import FastAPI
from .routes import customers, employees, loans, installments, purchases, payments
from app.utils.auth import router as auth_router  # Importamos el router de autenticación
from fastapi.middleware.cors import CORSMiddleware


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],      # o una lista de dominios
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"ok": True}


# Incluir las rutas en la app
app.include_router(customers.router, prefix="/customers", tags=["Customers"])
app.include_router(employees.router, prefix="/employees", tags=["Employees"])
app.include_router(loans.router, prefix="/loans", tags=["Loans"])
app.include_router(installments.router, prefix="/installments", tags=["Installments"])
app.include_router(purchases.router, prefix="/purchases", tags=["Purchases"])
app.include_router(payments.router, prefix="/payments", tags=["Payments"])


# Registrar el router de autenticación
app.include_router(auth_router)
