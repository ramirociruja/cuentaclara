import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.database.db import Base, SessionLocal, engine  # Usamos la base y la sesión del archivo db.py
from app.main import app  # Tu aplicación FastAPI
from fastapi.testclient import TestClient

# Usar SQLite en memoria para las pruebas
SQLALCHEMY_TEST_DATABASE_URL = "sqlite:///:memory:"  # Base de datos en memoria

# Crear un nuevo motor y una nueva sesión para las pruebas
engine_test = create_engine(SQLALCHEMY_TEST_DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocalTest = sessionmaker(autocommit=False, autoflush=False, bind=engine_test)

# Crear una base de datos y tablas solo para las pruebas
@pytest.fixture(scope="module")
def setup_db():
    # Crear todas las tablas en la base de datos en memoria
    Base.metadata.create_all(bind=engine_test)
    
    # Usar la sesión de la base de datos para las pruebas
    db = SessionLocalTest()
    yield db  # Esta base de datos se usará en las pruebas
    
    # Limpiar después de las pruebas
    db.close()
    Base.metadata.drop_all(bind=engine_test)

# Usar el cliente de FastAPI para las pruebas
@pytest.fixture(scope="module")
def client():
    return TestClient(app)

# Ejemplo de prueba para verificar los clientes
def test_create_customer(setup_db, client):
    customer_data = {
        "name": "Juan Perez",
        "address": "Calle Falsa 123",
        "phone": "123456789",
        "email": "juan@example.com",
        "employee_id": 1,
        "company_id": 1
    }
    
    # Usar el cliente para hacer una petición POST
    response = client.post("/customers/", json=customer_data)
    assert response.status_code == 200  # Verifica que la respuesta sea 200 OK
    created_customer = response.json()
    assert created_customer["name"] == customer_data["name"]  # Verifica que el cliente fue creado correctamente
