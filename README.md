# FastAPI + Flutter Starter Template

A production-ready full-stack starter template for building mobile apps with a Python API backend. Ships with JWT authentication, end-to-end testing, Docker orchestration, and GitHub Actions CI — all wired together and ready to customise.

---

## What's Included

| Layer | What you get |
|---|---|
| **Backend** | FastAPI app with register / login / refresh / me endpoints, bcrypt password hashing, JWT access + refresh tokens, security headers middleware, CORS |
| **Database** | PostgreSQL via Docker Compose, SQLAlchemy 2 ORM, Alembic migrations, initial `users` table |
| **Mobile** | Flutter app with Riverpod state management, Dio HTTP client with automatic token refresh + 401 retry, `go_router` auth-aware navigation, `flutter_secure_storage` token persistence |
| **Testing** | Backend: 15 pytest tests (SQLite in-memory, no Docker needed). Mobile: unit + widget tests with `mocktail` |
| **Linting** | Backend: `ruff` (lint + format) + `mypy` type checking. Mobile: `flutter analyze` |
| **CI/CD** | GitHub Actions: backend pipeline (lint → type-check → test → coverage), mobile pipeline (analyze → test → APK build on main) |
| **Docker** | Dev `docker-compose.yml` (postgres + backend), prod `docker-compose.prod.yml` overlay |

---

## Tech Stack

**Backend**
- Python 3.9+ · FastAPI 0.115 · SQLAlchemy 2 · Alembic · pydantic-settings v2
- python-jose (JWT) · passlib + bcrypt (password hashing)
- pytest · ruff · mypy

**Mobile**
- Flutter 3 (Dart 3) · Riverpod 2 · Dio 5 · go_router 14
- flutter_secure_storage · flutter_dotenv
- mocktail (testing)

**Infrastructure**
- PostgreSQL 16 · Docker Compose · GitHub Actions

---

## Prerequisites

- [Docker](https://www.docker.com/) (for the database)
- Python 3.9+ with `pip`
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.24+

---

## Quick Start

### 1. Clone and enter the repo

```bash
git clone <your-repo-url> myproject
cd myproject
```

### 2. Set up environment files

```bash
# Root .env — credentials for the postgres Docker container
cp .env.example .env

# Backend .env — application settings (JWT secret, CORS, etc.)
cp backend/.env.example backend/.env
```

Open `backend/.env` and replace `JWT_SECRET_KEY` with a real secret:

```bash
openssl rand -hex 32
# paste the output as the value of JWT_SECRET_KEY in backend/.env
```

### 3. Start PostgreSQL

```bash
docker compose up -d db
```

### 4. Install backend dependencies and run migrations

```bash
python3 -m venv backend/venv
source backend/venv/bin/activate      # Windows: backend\venv\Scripts\activate
pip install -r backend/requirements.txt

cd backend
alembic upgrade head
cd ..
```

### 5. Start the backend

```bash
cd backend
uvicorn app.main:app --reload
# API is now at http://localhost:8000
# Swagger UI at http://localhost:8000/docs
```

### 6. Run the mobile app

```bash
cd mobile
flutter pub get
flutter run
```

---

## Project Structure

```
.
├── .env.example                    # Root env template (postgres docker vars)
├── .env                            # Your local root env (gitignored)
├── .gitignore
├── docker-compose.yml              # Dev: postgres + backend services
├── docker-compose.prod.yml         # Prod overlay: restart policies, no bind mounts
├── README.md
├── SETUP_CHECKLIST.md              # Checklist for customising this template
│
├── .github/
│   └── workflows/
│       ├── backend-ci.yml          # Python CI: lint → type-check → test
│       └── mobile-ci.yml           # Flutter CI: analyze → test → APK
│
├── backend/
│   ├── .env.example                # Backend env template
│   ├── .env                        # Your local backend env (gitignored)
│   ├── Dockerfile
│   ├── alembic.ini
│   ├── pyproject.toml              # ruff + mypy + pytest config
│   ├── requirements.txt            # Runtime dependencies
│   ├── requirements-dev.txt        # Dev/test dependencies
│   ├── app/
│   │   ├── main.py                 # FastAPI app, middleware registration
│   │   ├── api/
│   │   │   ├── deps.py             # get_current_user dependency
│   │   │   └── v1/
│   │   │       ├── router.py
│   │   │       └── endpoints/
│   │   │           └── auth.py     # register / login / refresh / me
│   │   ├── core/
│   │   │   ├── config.py           # pydantic-settings Settings class
│   │   │   ├── database.py         # SQLAlchemy engine + session
│   │   │   └── security.py         # JWT encode/decode, password hashing
│   │   ├── middleware/
│   │   │   └── security.py         # Security response headers
│   │   ├── models/
│   │   │   └── user.py             # User SQLAlchemy model
│   │   └── schemas/
│   │       └── user.py             # Pydantic request/response schemas
│   ├── migrations/
│   │   ├── env.py
│   │   └── versions/
│   │       └── *_create_users_table.py
│   └── tests/
│       ├── conftest.py             # SQLite fixtures, TestClient, make_user
│       └── test_auth.py            # 15 tests covering all auth endpoints
│
└── mobile/
    ├── pubspec.yaml
    ├── .env                        # Flutter env (gitignored) — set API_BASE_URL
    ├── lib/
    │   ├── main.dart               # Entry point: dotenv load, ProviderScope
    │   ├── app.dart                # MaterialApp.router wired to routerProvider
    │   ├── core/
    │   │   ├── constants/
    │   │   │   └── api_constants.dart     # Base URL, route paths
    │   │   ├── network/
    │   │   │   ├── api_client.dart        # Dio wrapper, auth interceptor, token refresh
    │   │   │   ├── api_exception.dart     # Sealed exception hierarchy
    │   │   │   ├── base_repository.dart   # safeCall, withRetry, fetchPage
    │   │   │   ├── providers.dart         # apiClientProvider
    │   │   │   └── result.dart            # Result<T> (Ok / Err)
    │   │   ├── router/
    │   │   │   └── app_router.dart        # go_router with auth redirect guard
    │   │   └── security/
    │   │       └── secure_storage.dart    # flutter_secure_storage wrapper
    │   └── features/
    │       └── auth/
    │           ├── data/
    │           │   ├── auth_repository.dart    # login / register / getMe
    │           │   └── models/
    │           │       └── auth_models.dart    # TokenResponse, AppUser
    │           └── presentation/
    │               ├── auth_notifier.dart      # AuthNotifier + authProvider
    │               └── screens/
    │                   ├── login_screen.dart
    │                   └── register_screen.dart
    └── test/
        ├── widget_test.dart
        ├── helpers/
        │   └── test_helpers.dart           # FakeAuthNotifier, buildTestApp
        └── features/auth/
            ├── data/
            │   └── auth_repository_test.dart   # 10 unit tests (MockApiClient)
            └── presentation/
                └── login_screen_test.dart       # 12 widget tests
```

---

## Running Tests

**Backend** (no Docker required — uses SQLite in-memory):

```bash
cd backend
source venv/bin/activate
pytest                        # run all tests
pytest -v                     # verbose output
pytest --cov=app              # with coverage report
```

**Mobile**:

```bash
cd mobile
flutter test                  # run all tests
flutter test --coverage       # with coverage
```

---

## Auth Flow

```
POST /api/v1/auth/register   { email, password }  →  201 { access_token, refresh_token }
POST /api/v1/auth/login      { email, password }  →  200 { access_token, refresh_token }
GET  /api/v1/auth/me         Authorization: Bearer <access_token>  →  200 { user }
POST /api/v1/auth/refresh    { refresh_token }    →  200 { access_token, refresh_token }
```

The mobile `ApiClient` automatically refreshes the access token on 401 responses and retries
the original request — callers never need to handle token expiry manually.

---

## Environment Variables Reference

### Root `.env` (postgres docker service)

| Variable | Description | Example |
|---|---|---|
| `POSTGRES_USER` | Database user | `appuser` |
| `POSTGRES_PASSWORD` | Database password | `changeme` |
| `POSTGRES_DB` | Database name | `appdb` |
| `DATABASE_URL` | Full connection string (for scripts) | `postgresql://appuser:changeme@localhost:5432/appdb` |

### `backend/.env` (FastAPI app)

| Variable | Description | Example |
|---|---|---|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://appuser:changeme@localhost:5432/appdb` |
| `JWT_SECRET_KEY` | JWT signing secret — **generate with `openssl rand -hex 32`** | — |
| `JWT_ALGORITHM` | JWT algorithm | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Access token lifetime | `30` |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Refresh token lifetime | `7` |
| `BACKEND_CORS_ORIGINS` | Allowed origins (JSON array) | `["http://localhost:3000"]` |
| `ENV` | App environment | `development` |
| `DEBUG` | Debug mode | `false` |

### `mobile/.env` (Flutter app)

| Variable | Description | Example |
|---|---|---|
| `API_BASE_URL` | Backend base URL | `http://localhost:8000` |

---

## CI/CD

Both pipelines trigger on push and pull requests to `main` and `develop`, with path filters so each only runs when its own code changes.

**Backend CI** (`.github/workflows/backend-ci.yml`):
1. Lint with `ruff`
2. Type-check with `mypy`
3. Run `pytest` with coverage
4. Upload coverage to Codecov

**Mobile CI** (`.github/workflows/mobile-ci.yml`):
1. `flutter analyze`
2. `flutter test --coverage`
3. Upload coverage to Codecov
4. Build debug APK (main branch only)

To enable Codecov, add a `CODECOV_TOKEN` secret in your GitHub repository settings.

---

## Docker

**Development** (`docker-compose.yml`):
- `db` service: PostgreSQL 16 with health check, persistent named volume
- `backend` service: mounts `./backend` for live code reload

**Production** (`docker-compose.prod.yml` overlay):
- Adds `restart: always` to both services
- Removes the backend bind mount (uses the built image instead)

```bash
# Production startup
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## Customising This Template

See [SETUP_CHECKLIST.md](SETUP_CHECKLIST.md) for a step-by-step checklist to rename, configure, and extend this template for your specific project.
