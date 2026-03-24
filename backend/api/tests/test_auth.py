import os
import subprocess
import sys
import base64
import hashlib
import hmac
from pathlib import Path

from fastapi.testclient import TestClient

from main import Tenant, create_app


def make_client(tmp_path: Path) -> TestClient:
    database_path = tmp_path / "test-auth.db"
    app = create_app(f"sqlite:///{database_path}")
    return TestClient(app)


def register_and_login(client: TestClient, username: str = "releaseuser") -> dict:
    password = "StrongPass123"
    register_response = client.post(
        "/api/register",
        json={"username": username, "password": password, "tenant_name": "Revenue Ops"},
    )
    assert register_response.status_code == 200

    login_response = client.post(
        "/api/login",
        json={"username": username, "password": password},
    )
    assert login_response.status_code == 200
    return login_response.json()


def auth_headers(token: str, tenant_id: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "X-Tenant-Id": tenant_id,
    }


def test_register_persists_user_and_returns_profile(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/api/register",
        json={"username": "releaseuser", "password": "StrongPass123", "tenant_name": "Revenue Ops"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["user"]["username"] == "releaseuser"
    assert body["user"]["id"] >= 1
    assert body["tenant"]["id"] == "revenue-ops"


def test_register_rejects_duplicate_username(tmp_path: Path):
    client = make_client(tmp_path)
    payload = {"username": "duplicate", "password": "StrongPass123", "tenant_name": "Revenue Ops"}

    first = client.post("/api/register", json=payload)
    second = client.post("/api/register", json=payload)

    assert first.status_code == 200
    assert second.status_code == 409
    assert second.json()["detail"] == "username already exists"


def test_login_requires_persisted_credentials(tmp_path: Path):
    client = make_client(tmp_path)
    register_payload = {"username": "authuser", "password": "StrongPass123", "tenant_name": "Revenue Ops"}
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
        json={"username": "tiny", "password": "short", "tenant_name": "Revenue Ops"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "password must be at least 8 characters"


def test_register_rejects_invalid_username_characters(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/api/register",
        json={"username": "bad user", "password": "StrongPass123", "tenant_name": "Revenue Ops"},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "username may only contain letters, numbers, dots, dashes, and underscores"


def test_protected_endpoints_reject_invalid_status_payloads(tmp_path: Path):
    client = make_client(tmp_path)
    session = register_and_login(client)
    headers = auth_headers(session["access_token"], session["user"]["tenant_id"])

    lead_response = client.post(
        f"/webhook/{session['user']['tenant_id']}",
        json={
            "events": [
                {
                    "replyToken": "reply-token",
                    "source": {"userId": "u-123"},
                    "message": {"text": "price 0812345678"},
                }
            ]
        },
    )
    assert lead_response.status_code == 200

    patch_response = client.patch("/api/leads/1", json={"status": "invalid"}, headers=headers)
    filter_response = client.get("/api/leads?status=invalid", headers=headers)
    broadcast_response = client.post(
        "/api/broadcast",
        json={"name": "Launch", "message": "Hello", "target_status": "invalid"},
        headers=headers,
    )

    assert patch_response.status_code == 400
    assert filter_response.status_code == 400
    assert broadcast_response.status_code == 400
    assert patch_response.json()["detail"] == "status must be one of: new, cold, warm, hot, closed"


def test_template_and_broadcast_require_non_empty_messages(tmp_path: Path):
    client = make_client(tmp_path)
    session = register_and_login(client, username="opsuser")
    headers = auth_headers(session["access_token"], session["user"]["tenant_id"])

    template_response = client.post(
        "/api/templates",
        json={"name": "   ", "message": "   "},
        headers=headers,
    )
    broadcast_response = client.post(
        "/api/broadcast",
        json={"name": "Launch", "message": "   "},
        headers=headers,
    )

    assert template_response.status_code == 400
    assert template_response.json()["detail"] == "template name is required"
    assert broadcast_response.status_code == 400
    assert broadcast_response.json()["detail"] == "broadcast message is required"


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


def test_webhook_rejects_invalid_line_signature_when_secret_is_configured(tmp_path: Path):
    client = make_client(tmp_path)
    session = client.app.state.session_factory()
    session.add(Tenant(id="tenant-1", name="Tenant 1", line_channel_secret="top-secret"))
    session.commit()
    session.close()

    response = client.post(
        "/webhook/tenant-1",
        headers={"x-line-signature": "invalid"},
        json={"events": [{"replyToken": "reply", "source": {"userId": "u1"}, "message": {"text": "hello"}}]},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "invalid line signature"


def test_webhook_accepts_valid_line_signature_when_secret_is_configured(tmp_path: Path):
    client = make_client(tmp_path)
    session = client.app.state.session_factory()
    session.add(Tenant(id="tenant-2", name="Tenant 2", line_channel_secret="top-secret"))
    session.commit()
    session.close()

    payload = b'{"events":[{"replyToken":"reply","source":{"userId":"u1"},"message":{"text":"hello"}}]}'
    signature = base64.b64encode(hmac.new(b"top-secret", payload, hashlib.sha256).digest()).decode("utf-8")

    response = client.post(
        "/webhook/tenant-2",
        headers={"x-line-signature": signature, "content-type": "application/json"},
        content=payload,
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_import_with_default_sqlite_does_not_create_db_file(tmp_path: Path):
    api_root = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env.pop("DATABASE_URL", None)
    env["PYTHONPATH"] = str(api_root)

    result = subprocess.run(
        [sys.executable, "-c", "import main; print('ok')"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "ok"
    assert not (tmp_path / "zlinebot.db").exists()
