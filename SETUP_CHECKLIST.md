# Setup Checklist

Step-by-step guide for turning this template into your specific project.
Work through each section in order.

---

## 1. Clone and Create Your Repository

- [ ] Clone this template or use GitHub's "Use this template" button
- [ ] Create a new repository for your project
- [ ] Update the remote: `git remote set-url origin <your-new-repo-url>`

---

## 2. Choose Your App Name

Pick a name for your project. You'll use it in several places below.
A good pattern: lowercase with underscores for code (`my_app`), title case for display (`My App`).

---

## 3. Rename the Flutter Package

The Flutter package name appears in `mobile/pubspec.yaml` and in the platform-specific
bundle identifiers on Android and iOS.

**`mobile/pubspec.yaml`**
```yaml
name: your_app_name          # was: myapp
description: "Your app description."
```

**Android bundle ID** — `mobile/android/app/build.gradle`:
```gradle
applicationId "com.yourcompany.yourappname"
```

**iOS bundle ID** — open `mobile/ios/Runner.xcodeproj` in Xcode:
- Select the Runner target → General → Bundle Identifier
- Change to `com.yourcompany.yourappname`

> After renaming, run `flutter pub get` to pick up the change.

---

## 4. Update the App Title

**`mobile/lib/app.dart`** — shown in the app switcher and as the default window title:
```dart
title: 'Your App Name',    // was: 'MyApp'
```

---

## 5. Update the API Title

**`backend/app/main.py`** — shown in the `/docs` Swagger UI:
```python
app = FastAPI(title="Your App API", ...)
```

---

## 6. Set Up Environment Files

**Root `.env`** (postgres docker service):
```bash
cp .env.example .env
```
Edit `.env` and choose your database credentials:
```
POSTGRES_USER=yourdbuser
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=yourappdb
DATABASE_URL=postgresql://yourdbuser:<strong-password>@localhost:5432/yourappdb
```

**`backend/.env`** (FastAPI application):
```bash
cp backend/.env.example backend/.env
```
Edit `backend/.env`:
- [ ] Set `DATABASE_URL` to match the credentials above
- [ ] Generate and set `JWT_SECRET_KEY`:
  ```bash
  openssl rand -hex 32
  ```
- [ ] Set `BACKEND_CORS_ORIGINS` to your frontend's origin(s)

**`mobile/.env`** (Flutter app):
```bash
# Create the file — it is loaded as a Flutter asset
echo "API_BASE_URL=http://localhost:8000" > mobile/.env
```
For production, set `API_BASE_URL` to your deployed backend URL.

> The `mobile/.env` file is listed in `mobile/pubspec.yaml` as a Flutter asset
> and is gitignored by default. Add a `mobile/.env.example` if you want to
> document the required variables.

---

## 7. Start the Database and Run Migrations

```bash
docker compose up -d db

cd backend
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head
```

Verify the `users` table was created:
```bash
# If you have psql available:
psql postgresql://yourdbuser:yourpassword@localhost:5432/yourappdb -c "\d users"
```

---

## 8. Add Your First Alembic Migration (Optional)

If you want to add columns to the `users` table or create new tables, generate
a new migration after changing the SQLAlchemy models:

```bash
cd backend
alembic revision --autogenerate -m "describe_your_change"
alembic upgrade head
```

> Keep the initial `create_users_table` migration intact — it is the foundation
> of the migration history.

---

## 9. Verify the Backend Runs

```bash
cd backend
uvicorn app.main:app --reload
```

- [ ] `GET http://localhost:8000/health` returns `{"status": "ok"}`
- [ ] `GET http://localhost:8000/docs` shows the Swagger UI
- [ ] Test register: `POST /api/v1/auth/register` with `{"email": "...", "password": "..."}`

---

## 10. Verify the Tests Pass

```bash
cd backend
ruff check .         # should be clean
mypy app             # should be clean
pytest               # should show 15 passed
```

---

## 11. Run the Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

- [ ] App launches and shows the login screen
- [ ] Register with a test account
- [ ] Login redirects to the home screen
- [ ] Logout redirects back to login

---

## 12. Configure GitHub Actions

The CI workflows are in `.github/workflows/` and will run automatically on push.
A few things to configure in your GitHub repository settings:

**Secrets** (Settings → Secrets and variables → Actions):
- [ ] `CODECOV_TOKEN` — get from [codecov.io](https://codecov.io) after linking your repo

**Branch protection** (Settings → Branches → Add rule for `main`):
- [ ] Require status checks to pass before merging
  - Required checks: `Lint, type-check & test (Python 3.9)` (backend), `Analyze & Test` (mobile)
- [ ] Require branches to be up to date before merging

---

## 13. Add Your Own Features

The auth system is complete. Here's the recommended pattern for adding new features:

**Backend** — new feature in `app/api/v1/endpoints/your_feature.py`:
```python
from fastapi import APIRouter, Depends
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter()

@router.get("/your-endpoint")
def your_endpoint(current_user: User = Depends(get_current_user)):
    return {"user_id": str(current_user.id)}
```

Register it in `app/api/v1/router.py`:
```python
from app.api.v1.endpoints import your_feature
router.include_router(your_feature.router, prefix="/your-feature", tags=["your-feature"])
```

**Mobile** — new feature repository in `lib/features/your_feature/data/`:
```dart
class YourRepository extends BaseRepository {
  const YourRepository(super.client);

  Future<Result<YourModel>> fetchSomething() =>
      safeCall(() => client.get(
            '${ApiConstants.v1}/your-feature/your-endpoint',
            fromJson: (d) => YourModel.fromJson(d as Map<String, dynamic>),
          ));
}
```

Use `apiClientProvider` in a Riverpod provider to share the authenticated `ApiClient`:
```dart
final yourRepoProvider = Provider((ref) =>
    YourRepository(ref.watch(apiClientProvider)));
```

---

## 14. Update This README

Once your project is running, update `README.md`:
- [ ] Replace the template description with your project's purpose
- [ ] Update the tech stack section if you've added or changed dependencies
- [ ] Add any project-specific setup steps
- [ ] Remove or update the "Customising This Template" section
- [ ] Delete `SETUP_CHECKLIST.md` (this file) once you're done

---

## Summary Checklist

| Step | Item | Done |
|---|---|---|
| 3 | Flutter package name in `pubspec.yaml` | ☐ |
| 3 | Android bundle ID | ☐ |
| 3 | iOS bundle ID | ☐ |
| 4 | App title in `app.dart` | ☐ |
| 5 | API title in `main.py` | ☐ |
| 6 | Root `.env` with database credentials | ☐ |
| 6 | `backend/.env` with JWT secret | ☐ |
| 6 | `mobile/.env` with API base URL | ☐ |
| 7 | Database started and migrations applied | ☐ |
| 10 | All backend tests pass | ☐ |
| 11 | Mobile app runs and auth works end-to-end | ☐ |
| 12 | `CODECOV_TOKEN` secret added to GitHub | ☐ |
| 12 | Branch protection rules configured | ☐ |
| 14 | README updated for your project | ☐ |
