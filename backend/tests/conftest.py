"""
Pytest configuration and shared fixtures.

Database strategy: SQLite in-memory with StaticPool gives fast, fully-isolated
tests — no Docker or running PostgreSQL required. Every test function gets a
fresh database (tables created, then dropped after the test).
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.deps import get_db
from app.core.database import Base
from app.core.security import hash_password
from app.main import app
from app.models.user import User

# ─── Database ─────────────────────────────────────────────────────────────────


@pytest.fixture
def engine():
    """
    Fresh in-memory SQLite database per test function.

    StaticPool ensures all connections within a test share the same
    single in-memory database, so data committed by one session is
    immediately visible to another.
    """
    eng = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=eng)
    yield eng
    Base.metadata.drop_all(bind=eng)
    eng.dispose()


# ─── HTTP client ──────────────────────────────────────────────────────────────


@pytest.fixture
def client(engine):
    """
    FastAPI TestClient wired to the test database.

    Overrides the ``get_db`` dependency so every request the test makes
    uses the same in-memory SQLite engine as the rest of the fixtures.
    """
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as tc:
        yield tc
    app.dependency_overrides.pop(get_db, None)


# ─── User factory ─────────────────────────────────────────────────────────────


@pytest.fixture
def make_user(engine):
    """
    Factory that inserts a User directly into the test database.

    Usage::

        def test_something(make_user):
            user = make_user(email="foo@bar.com", password="secret123")
            inactive = make_user(email="x@y.com", is_active=False)
    """
    Session = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def _make(
        *,
        email: str = "test@example.com",
        password: str = "password123",
        is_active: bool = True,
    ) -> User:
        db = Session()
        try:
            user = User(
                email=email,
                hashed_password=hash_password(password),
                is_active=is_active,
            )
            db.add(user)
            db.commit()
            db.refresh(user)
            return user
        finally:
            db.close()

    return _make


# ─── Authenticated client ─────────────────────────────────────────────────────


@pytest.fixture
def auth_client(client, make_user):
    """
    TestClient pre-configured with a valid Bearer token.

    Creates a test user via ``make_user``, logs them in through the API,
    and attaches the returned access token to every subsequent request.
    """
    make_user(email="auth@example.com", password="password123")
    res = client.post(
        "/api/v1/auth/login",
        json={"email": "auth@example.com", "password": "password123"},
    )
    assert res.status_code == 200, f"auth_client login failed: {res.json()}"

    token = res.json()["access_token"]
    client.headers = {**client.headers, "Authorization": f"Bearer {token}"}
    return client
