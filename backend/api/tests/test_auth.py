import os
import subprocess
import sys
from pathlib import Path

from fastapi.testclient import TestClient

from main import create_app


def make_client(tmp_path: Path) -> TestClient:
    database_path = tmp_path / "test-auth.db"
    app = create_app(f"sqlite:///{database_path}")
    return TestClient(app)


def test_register_persists_user_and_returns_profile(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/api/register",
        json={"username": "releaseuser", "password": "StrongPass123"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["user"]["username"] == "releaseuser"
    assert body["user"]["id"] >= 1


def test_register_rejects_duplicate_username(tmp_path: Path):
    client = make_client(tmp_path)
    payload = {"username": "duplicate", "password": "StrongPass123"}

    first = client.post("/api/register", json=payload)
    second = client.post("/api/register", json=payload)

    assert first.status_code == 200
    assert second.status_code == 409
    assert second.json()["detail"] == "username already exists"


def test_login_requires_persisted_credentials(tmp_path: Path):
    client = make_client(tmp_path)
    register_payload = {"username": "authuser", "password": "StrongPass123"}
    client.post("/api/register", json=register_payload)

    success = client.post("/api/login", json=register_payload)
    failure = client.post(
        "/api/login",
        json={"username": "authuser", "password": "WrongPass123"},
    )
    missing = client.post(
        "/api/login",
        json={"username": "nouser", "password": "StrongPass123"},
    )

    assert success.status_code == 200
    assert success.json()["token_type"] == "bearer"
    assert success.json()["user"]["username"] == "authuser"
    assert failure.status_code == 401
    assert missing.status_code == 401
    assert failure.json()["detail"] == "invalid credentials"
    assert missing.json()["detail"] == "invalid credentials"


def test_register_rejects_short_passwords(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/api/register",
        json={"username": "tiny", "password": "short"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "password must be at least 8 characters"


def test_import_does_not_touch_database_at_module_import(tmp_path: Path):
    env = os.environ.copy()
    env["DATABASE_URL"] = "postgresql://invalid:invalid@127.0.0.1:1/not-used"

    result = subprocess.run(
        [sys.executable, "-c", "import main; print('ok')"],
        cwd=Path(__file__).resolve().parents[1],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "ok"
