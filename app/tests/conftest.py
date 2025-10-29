# app/tests/conftest.py
import os
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

from app.main import app
from app.database.db import Base, get_db
from app.models.models import Company, Employee
from app.utils.auth import hash_password, create_access_token

# Usá SQLite en archivo para evitar problemas de conexión en memoria
TEST_DB_URL = os.getenv("TEST_DATABASE_URL", "sqlite:///./test_unit.db")

# ---------- ENGINE (session-scoped) ----------
@pytest.fixture(scope="session")
def engine():
    """
    Engine único para la sesión de tests.
    """
    eng = create_engine(TEST_DB_URL, future=True, echo=False)
    # Creamos una vez al inicio para garantizar que exista el archivo si es SQLite
    Base.metadata.create_all(eng)
    yield eng
    # Limpieza final
    Base.metadata.drop_all(eng)

# ---------- DB (function-scoped) ----------
@pytest.fixture
def db(engine):
    """
    Base limpia por test: dropea y crea tablas antes de cada test para
    evitar colisiones de UNIQUE entre casos (dni/phone/email).
    """
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)

    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()

# ---------- Override de get_db ----------
@pytest.fixture(autouse=True)
def _override_db(db):
    def _get_db():
        try:
            yield db
        finally:
            pass
    app.dependency_overrides[get_db] = _get_db
    yield
    app.dependency_overrides.pop(get_db, None)

# ---------- Cliente FastAPI ----------
@pytest.fixture
def client():
    return TestClient(app)

# ---------- Seed: Company + Admin ----------
@pytest.fixture
def seeded_admin(db):
    """
    Crea Company (sin 'status') y Employee admin.
    Employee usa 'password' (hash) y login por 'username' (tu email).
    """
    company = Company(name="Test Co")
    db.add(company)
    db.flush()

    admin = Employee(
        name="Admin",
        role="admin",
        phone="3810000000",
        email="admin@test.local",
        password=hash_password("123456"),  # tu modelo usa 'password'
        company_id=company.id,
    )
    db.add(admin)
    db.commit()
    db.refresh(admin)
    return company, admin

# ---------- Header Authorization ----------
@pytest.fixture
def auth_headers(seeded_admin):
    _, admin = seeded_admin
    access = create_access_token(admin)  # tu utilidad recibe el Employee
    return {"Authorization": f"Bearer {access}"}
