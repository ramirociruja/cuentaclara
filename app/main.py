import os
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.routes import tasks


from .routes import customers, employees, loans, installments, purchases, payments, companies
from app.utils.auth import router as auth_router  # Importamos el router de autenticación
from fastapi.middleware.cors import CORSMiddleware
import logging


app = FastAPI()

ENV = os.getenv("ENV", "dev").lower()
_raw = os.getenv("CORS_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _raw.split(",") if o.strip()]

if ENV == "prod":
    if not ALLOWED_ORIGINS:
        print("⚠️  CORS_ORIGINS vacío en prod (permitido porque solo app móvil accede a la API).")
        ALLOWED_ORIGINS = []
    elif any(o == "*" for o in ALLOWED_ORIGINS):
        raise RuntimeError('En prod, CORS_ORIGINS no puede contener "*". Definí dominios explícitos.')
    allow_credentials = False
else:
    if not ALLOWED_ORIGINS:
        ALLOWED_ORIGINS = ["*"]
    allow_credentials = False



app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "Origin",
        "X-Requested-With",
    ],
    expose_headers=["Content-Disposition"],  # útil si descargas archivos
    max_age=600,  # cachea el preflight 10 min
)




logger = logging.getLogger("uvicorn.error")

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc: RequestValidationError):
    logger.error("422 detail: %s", exc.errors())
    return JSONResponse(status_code=422, content={"detail": exc.errors()})

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
app.include_router(companies.router, prefix="/companies", tags=["Companies"])
app.include_router(tasks.router)


# Registrar el router de autenticación
app.include_router(auth_router)


if os.getenv("ENABLE_SCHEDULER", "false").lower() == "true":
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    from apscheduler.triggers.cron import CronTrigger
    from app.jobs.overdue import mark_overdue_installments_job
    from zoneinfo import ZoneInfo

    tz = ZoneInfo("America/Argentina/Tucuman")
    scheduler = AsyncIOScheduler(timezone=tz)

    @app.on_event("startup")
    async def _start_scheduler():
        # Todos los días 02:00 (TZ Tucumán)
        scheduler.add_job(
            mark_overdue_installments_job,
            CronTrigger(hour=2, minute=0, timezone=tz),
            id="mark-overdue-daily",
            replace_existing=True,
        )
        scheduler.start()
