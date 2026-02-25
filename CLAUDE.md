# Template Briefing

## Overview
Full-stack mobile starter template. FastAPI backend + Flutter mobile frontend, PostgreSQL database, Docker orchestration, JWT auth, CI/CD pipelines.

## Stack
- **Backend**: FastAPI, SQLAlchemy 2, Alembic, PostgreSQL, JWT auth (python-jose + passlib)
- **Mobile**: Flutter (Dart), Dio, go_router, Riverpod, flutter_secure_storage, flutter_dotenv
- **Infra**: Docker Compose (PostgreSQL + backend), GitHub Actions CI

## Project Structure
```
project/
├── backend/
│   ├── app/
│   │   ├── api/v1/endpoints/   # Route handlers
│   │   ├── core/               # Config, database, security
│   │   ├── middleware/         # Security headers
│   │   ├── models/             # SQLAlchemy models
│   │   └── schemas/            # Pydantic schemas
│   ├── migrations/             # Alembic migrations
│   ├── tests/                  # pytest (SQLite in-memory)
│   ├── requirements.txt
│   ├── requirements-dev.txt
│   ├── pyproject.toml          # ruff + mypy + pytest config
│   └── Dockerfile
├── mobile/
│   ├── lib/
│   │   ├── core/               # Network, router, security, constants
│   │   ├── features/auth/      # Auth feature (data + presentation)
│   │   ├── main.dart
│   │   └── app.dart
│   └── test/                   # Flutter unit + widget tests
├── .github/workflows/
│   ├── backend-ci.yml          # ruff + mypy + pytest + codecov
│   └── mobile-ci.yml           # flutter analyze + test + APK build
├── docker-compose.yml          # Dev: postgres + backend
├── docker-compose.prod.yml     # Prod overlay: restart policies
├── .env.example                # Root env template (postgres docker vars)
└── backend/.env.example        # Backend env template (app settings)
```

## API
- Base URL: `http://localhost:8000`
- API prefix: `/api/v1`
- Auth endpoints: `/api/v1/auth/{register,login,refresh,me}`
- Health check: `GET /health`
- Docs (dev only): `/docs`

## Environment Files
- Root `.env` → postgres docker service (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`)
- `backend/.env` → FastAPI app settings (DATABASE_URL, JWT config, CORS, etc.)
- `mobile/.env` → Flutter app settings (`API_BASE_URL`)

## Common Commands

### Backend
```bash
# Create and activate virtual environment
python3 -m venv backend/venv && source backend/venv/bin/activate

# Install dev dependencies
pip install -r backend/requirements-dev.txt

# Run locally (requires running postgres)
cd backend && uvicorn app.main:app --reload

# Run migrations
cd backend && alembic upgrade head

# Lint + type-check + test
cd backend && ruff check . && mypy app && pytest
```

### Mobile
```bash
cd mobile
flutter pub get
flutter run
flutter test
```

### Docker
```bash
# Start postgres only (for local backend dev)
docker compose up -d db

# Start all services
docker compose up -d

# Production overlay
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
