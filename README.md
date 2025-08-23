# CuentaClara

Sistema de gestión de **cobranzas y ventas** con:
- **Backend:** Python (FastAPI, SQLAlchemy, Alembic, PostgreSQL)
- **Frontend:** Flutter
- Uso personal (por ahora) y sin CI/CD.

---

## 🧭 Objetivo de este README
Que **cualquier persona (incluyéndome a futuro)** pueda clonar el repo y **correr backend + frontend** sin adivinar nada.  
También me sirve para hacerte una **code review completa** con el contexto correcto.

---

## ⚙️ Stack
**Backend**
- Python 3.10+
- FastAPI, SQLAlchemy, Alembic
- PostgreSQL 15+
- `python-dotenv` para leer `.env`
- Servidor de desarrollo: `uvicorn`

**Frontend**
- Flutter 3.x
- Dart 3.x

---

## 🗂️ Estructura del proyecto (resumen)
```
CUENTACLARA/
├─ app/                  # Backend (FastAPI)
│  ├─ database/
│  ├─ models/
│  ├─ routes/
│  ├─ schemas/
│  ├─ utils/
│  ├─ config.py
│  ├─ crud.py
│  └─ main.py
├─ alembic/              # Migraciones de BD
├─ frontend/             # App Flutter
│  ├─ lib/
│  ├─ assets/
│  ├─ pubspec.yaml
│  └─ analysis_options.yaml
├─ .env                  # Variables de entorno (NO subir a git)
└─ README.md
```

---

## ✅ Requisitos previos
- **Python 3.10+**
- **PostgreSQL 15+** (o compatible)
- **Flutter 3.x + Dart 3.x**
- **Git**

> **Nota:** Este proyecto usa **.env** con `DATABASE_URL` para el backend.

---

## 🔐 Variables de entorno
Crear un archivo `.env` en la raíz del proyecto con:

```env
# Backend
DATABASE_URL=postgresql://postgres:tu_password@localhost:5432/cuentaclara_db

# (Opcional) Si usás otra configuración, agregala aquí:
# APP_ENV=dev
# APP_PORT=8000
```

> ⚠️ No subas `.env` al repositorio (agregar a `.gitignore`).

---

## 🐘 Base de datos
1. Asegurate de tener PostgreSQL ejecutándose.
2. Creá la base de datos si no existe:
   ```sql
   CREATE DATABASE cuentaclara_db;
   ```

---

## 🚀 Backend (FastAPI)

### 1) Crear y activar entorno virtual
```bash
# En la raíz del repo
python -m venv .venv
# Linux/Mac
source .venv/bin/activate
# Windows (PowerShell)
.venv\Scripts\Activate.ps1
```

### 2) Instalar dependencias
> No había `requirements.txt`, así que estas son las **dependencias mínimas sugeridas**.  
> Copiá/pegá esto en un archivo `requirements.txt` (o instalalas manualmente).

```txt
fastapi==0.115.0
uvicorn[standard]==0.30.6
sqlalchemy==2.0.32
alembic==1.13.2
psycopg2-binary==2.9.9
pydantic==2.8.2
python-dotenv==1.0.1
```
Instalación:
```bash
pip install -r requirements.txt
```

### 3) Migraciones (Alembic)
Si ya tenés el directorio `alembic/` creado y configurado, corré:
```bash
alembic upgrade head
```
> Si falla por conexión: revisá `DATABASE_URL` del `.env` y la configuración en `app/config.py`.

### 4) Levantar el servidor
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
Docs interactivas:
- Swagger UI: http://127.0.0.1:8000/docs
- ReDoc: http://127.0.0.1:8000/redoc

---

## 📱 Frontend (Flutter)

1) Ir a la carpeta del frontend e instalar dependencias:
```bash
cd frontend
flutter pub get
```

2) (Si corresponde) Configurar la URL del backend en el código Flutter.  
   - **Ejemplo recomendado:** crear `lib/core/config.dart` (o usar tu archivo existente) con:
     ```dart
     class AppConfig {
       static const String apiBaseUrl = String.fromEnvironment(
         'API_BASE_URL',
         defaultValue: 'http://127.0.0.1:8000',
       );
     }
     ```
   - Y compilar con:
     ```bash
     flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
     ```
   - Si no usás `--dart-define`, asegurate de que el archivo donde tengas la URL del backend apunte a `http://127.0.0.1:8000` o la que corresponda.

3) Ejecutar la app:
```bash
flutter run
```

---

## 🧪 Tests
Actualmente **no hay tests** configurados. Futuro (sugerido):
- **Backend (pytest):**
  ```bash
  pytest -q
  ```
- **Frontend (Flutter):**
  ```bash
  flutter test
  ```

---

## 🧹 Formato y calidad (opcional)
Sugerencias a futuro:
- **Python:** `ruff`, `black`, `mypy`, `bandit`
- **Flutter:** mantener `analysis_options.yaml` y usar `dart fix --apply`  
Comandos útiles:
```bash
# Flutter
flutter analyze
dart fix --apply
```

---

## 🧰 Comandos rápidos (cheat sheet)
```bash
# Crear entorno e instalar (backend)
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Migrar BD
alembic upgrade head

# Correr backend
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Correr frontend
cd frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

---

## 🐞 Troubleshooting
- **`psycopg2`/conexión falla:** verificar `DATABASE_URL`, que Postgres esté activo y que la DB `cuentaclara_db` exista.
- **`alembic` error al conectar:** confirmar que Alembic lee el `.env` o que `alembic.ini`/`config.py` toman `DATABASE_URL` correctamente.
- **La app Flutter no llega al backend:** confirmar la **URL del backend** usada por el frontend y que el servidor esté levantado.
- **CORS:** si el frontend y backend corren en hosts/puertos distintos, configurar CORS en FastAPI.

---

## 📋 Para la code review (lo que voy a mirar)
- Estructura (capas, responsabilidades)
- Rutas y contratos de API
- Modelos/ORM y migraciones
- Manejo de errores, seguridad básica, validaciones
- Estado y consumo de API en Flutter (capa de servicios)
- Consistencia de estilos y nombres
- Posibles mejoras de performance/UX

> Si hay **pantallas/endpoints con errores conocidos**, listalos acá para priorizarlos.

---

## 📎 Notas
- **No uso Docker por ahora.** (se puede agregar más adelante si te interesa)
- Repo pensado para **uso personal**.

---

## 📝 Licencia
Uso personal (no especificada). Puedes agregar una licencia cuando corresponda.
