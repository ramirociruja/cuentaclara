import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# Routers (usar imports absolutos para evitar issues según cómo se ejecute uvicorn)
from app.routes import admin_license, customers, employees, loans, installments, purchases, payments, companies, tasks
from app.utils.auth import router as auth_router  # Router de autenticación

# -----------------------------------------------------------------------------
# Logging base
# -----------------------------------------------------------------------------
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("uvicorn.error")

# -----------------------------------------------------------------------------
# Lifespan: reemplaza on_event(startup/shutdown) con soporte de scheduler opcional
# -----------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Maneja inicio y cierre de la app. Si ENABLE_SCHEDULER=true,
    inicia APScheduler al levantar y lo detiene al apagar.
    """
    scheduler = None

    if os.getenv("ENABLE_SCHEDULER", "false").lower() == "true":
        try:
            from apscheduler.schedulers.asyncio import AsyncIOScheduler
            from apscheduler.triggers.cron import CronTrigger
            from zoneinfo import ZoneInfo
            from app.jobs.overdue import mark_overdue_installments_job

            tz = ZoneInfo("America/Argentina/Tucuman")
            hour = int(os.getenv("SCHED_HOUR", "2"))
            minute = int(os.getenv("SCHED_MINUTE", "0"))

            scheduler = AsyncIOScheduler(timezone=tz)
            scheduler.add_job(
                mark_overdue_installments_job,
                CronTrigger(hour=hour, minute=minute, timezone=tz),
                id="mark-overdue-daily",
                replace_existing=True,
                max_instances=1,     # evita superposiciones
                coalesce=True,       # si se salteó por caída, ejecuta una sola
                misfire_grace_time=3600,  # tolera hasta 1h de “missed run”
            )
            scheduler.start()
            logger.info("✅ Scheduler iniciado: %02d:%02d TZ=%s", hour, minute, tz.key)
        except Exception as e:
            logger.exception("❌ Error iniciando scheduler: %s", e)

    try:
        # ---- aplicación corriendo ----
        yield
    finally:
        if scheduler:
            try:
                scheduler.shutdown(wait=False)
                logger.info("🛑 Scheduler detenido correctamente")
            except Exception as e:
                logger.exception("⚠️ Error al detener scheduler: %s", e)

# -----------------------------------------------------------------------------
# App
# -----------------------------------------------------------------------------
app = FastAPI(lifespan=lifespan)

# -----------------------------------------------------------------------------
# CORS por entorno
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Handlers y health
# -----------------------------------------------------------------------------
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc: RequestValidationError):
    logger.error("422 detail: %s", exc.errors())
    return JSONResponse(status_code=422, content={"detail": exc.errors()})

@app.get("/health")
def health():
    return {"ok": True}

# (Opcional) compat k8s/PAAS
@app.get("/healthz")
def healthz():
    return {"ok": True}

# -----------------------------------------------------------------------------
# Routers
# -----------------------------------------------------------------------------
app.include_router(customers.router,     prefix="/customers",     tags=["Customers"])
app.include_router(employees.router,     prefix="/employees",     tags=["Employees"])
app.include_router(loans.router,         prefix="/loans",         tags=["Loans"])
app.include_router(installments.router,  prefix="/installments",  tags=["Installments"])
app.include_router(purchases.router,     prefix="/purchases",     tags=["Purchases"])
app.include_router(payments.router,      prefix="/payments",      tags=["Payments"])
app.include_router(companies.router,     prefix="/companies",     tags=["Companies"])
app.include_router(tasks.router)
app.include_router(auth_router)
app.include_router(admin_license.router, tags=["Admin"])