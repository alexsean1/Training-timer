"""
Auth endpoint integration tests.

Each test class corresponds to one endpoint or logical scenario.
All tests receive fresh fixtures from conftest.py and run against
an isolated in-memory SQLite database, so they are order-independent
and can run in parallel.
"""

VALID = {"email": "user@example.com", "password": "password123"}


# ─── POST /api/v1/auth/register ───────────────────────────────────────────────


class TestRegister:
    def test_success_returns_201_with_tokens(self, client):
        res = client.post("/api/v1/auth/register", json=VALID)

        assert res.status_code == 201
        body = res.json()
        assert "access_token" in body
        assert "refresh_token" in body
        assert body["token_type"] == "bearer"

    def test_duplicate_email_returns_409(self, client):
        client.post("/api/v1/auth/register", json=VALID)
        res = client.post("/api/v1/auth/register", json=VALID)

        assert res.status_code == 409

    def test_password_too_short_returns_422(self, client):
        res = client.post(
            "/api/v1/auth/register",
            json={"email": "a@example.com", "password": "short"},
        )

        assert res.status_code == 422

    def test_invalid_email_returns_422(self, client):
        res = client.post(
            "/api/v1/auth/register",
            json={"email": "not-an-email", "password": "password123"},
        )

        assert res.status_code == 422


# ─── POST /api/v1/auth/login ──────────────────────────────────────────────────


class TestLogin:
    def test_success_returns_200_with_tokens(self, client):
        client.post("/api/v1/auth/register", json=VALID)
        res = client.post("/api/v1/auth/login", json=VALID)

        assert res.status_code == 200
        body = res.json()
        assert "access_token" in body
        assert "refresh_token" in body

    def test_wrong_password_returns_401_with_www_authenticate(self, client):
        client.post("/api/v1/auth/register", json=VALID)
        res = client.post(
            "/api/v1/auth/login",
            json={**VALID, "password": "wrongpassword"},
        )

        assert res.status_code == 401
        assert res.headers.get("WWW-Authenticate") == "Bearer"

    def test_unknown_email_returns_401(self, client):
        res = client.post("/api/v1/auth/login", json=VALID)

        assert res.status_code == 401
        assert res.headers.get("WWW-Authenticate") == "Bearer"


# ─── POST /api/v1/auth/refresh ────────────────────────────────────────────────


class TestRefresh:
    def test_success_returns_new_tokens(self, client):
        reg = client.post("/api/v1/auth/register", json=VALID)
        refresh_token = reg.json()["refresh_token"]

        res = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})

        assert res.status_code == 200
        body = res.json()
        assert "access_token" in body
        assert "refresh_token" in body

    def test_invalid_token_returns_401(self, client):
        res = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": "invalid.token.here"},
        )

        assert res.status_code == 401
        assert res.headers.get("WWW-Authenticate") == "Bearer"

    def test_access_token_rejected_as_refresh(self, client):
        """An access token must not be accepted in the refresh endpoint."""
        reg = client.post("/api/v1/auth/register", json=VALID)
        access_token = reg.json()["access_token"]

        res = client.post(
            "/api/v1/auth/refresh",
            json={"refresh_token": access_token},
        )

        assert res.status_code == 401


# ─── GET /api/v1/auth/me ──────────────────────────────────────────────────────


class TestMe:
    def test_authenticated_user_gets_profile(self, auth_client):
        res = auth_client.get("/api/v1/auth/me")

        assert res.status_code == 200
        body = res.json()
        assert body["email"] == "auth@example.com"
        assert "id" in body
        assert body["is_active"] is True
        assert "created_at" in body
        assert "updated_at" in body

    def test_no_token_returns_401_with_www_authenticate(self, client):
        res = client.get("/api/v1/auth/me")

        assert res.status_code == 401
        assert res.headers.get("WWW-Authenticate") == "Bearer"

    def test_invalid_token_returns_401(self, client):
        res = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer invalid.token.here"},
        )

        assert res.status_code == 401
        assert res.headers.get("WWW-Authenticate") == "Bearer"

    def test_refresh_token_rejected_as_access(self, client):
        """A refresh token must not grant access to protected endpoints."""
        reg = client.post("/api/v1/auth/register", json=VALID)
        refresh_token = reg.json()["refresh_token"]

        res = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )

        assert res.status_code == 401

    def test_inactive_user_returns_403(self, client, make_user):
        """Inactive users can still authenticate but cannot access resources."""
        make_user(email="inactive@example.com", password="password123", is_active=False)

        login = client.post(
            "/api/v1/auth/login",
            json={"email": "inactive@example.com", "password": "password123"},
        )
        # login itself succeeds — the is_active check lives in get_current_user
        assert login.status_code == 200

        token = login.json()["access_token"]
        res = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert res.status_code == 403
