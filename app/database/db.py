from sqlalchemy import create_engine, MetaData
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv # type: ignore
import os

# Cargar variables de entorno
load_dotenv()

# URL de la base de datos desde el .env con un valor por defecto para desarrollo y pruebas
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./test.db")

# Configurar argumentos de conexión adicionales para SQLite
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

# Crear el motor de conexión
engine = create_engine(DATABASE_URL, connect_args=connect_args)

# Crear una sesión
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base para modelos
Base = declarative_base()
metadata = MetaData()

# Importar los modelos para garantizar que las tablas se registren correctamente
from app.models import models  # noqa: E402,F401

# Crear todas las tablas si aún no existen
Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

