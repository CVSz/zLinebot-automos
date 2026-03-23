import binascii
import base64
import hashlib
import hmac
import os
import sqlite3
from contextlib import asynccontextmanager, contextmanager
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException
from jose import jwt
from pydantic import BaseModel

try:
    import psycopg
    from psycopg.rows import dict_row
except ImportError:  # pragma: no cover - psycopg is installed in production requirements
    psycopg = None
    dict_row = None

JWT_ALG = "HS256"
JWT_SECRET = os.getenv("JWT_SECRET_CURRENT", "dev-secret")
DEFAULT_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./zlinebot.db")


class AuthPayload(BaseModel):
    username: str
    password: str


class ChatPayload(BaseModel):
    message: str


class UserStore:
    def __init__(self, database_url: str):
        self.database_url = database_url
        self.parsed_url = urlparse(database_url)
        self.is_sqlite = self.parsed_url.scheme == "sqlite"
        if not self.is_sqlite and psycopg is None:
            raise RuntimeError("psycopg is required for non-sqlite databases")

    def initialize(self) -> None:
        statements = self._schema_statements()
        with self.connection() as connection:
            cursor = connection.cursor()
            for statement in statements:
                cursor.execute(statement)
            connection.commit()

    @contextmanager
    def connection(self):
        if self.is_sqlite:
            connection = sqlite3.connect(self._sqlite_path())
            connection.row_factory = sqlite3.Row
            try:
                yield connection
            finally:
                connection.close()
            return

        connection = psycopg.connect(self.database_url, row_factory=dict_row)
        try:
            yield connection
        finally:
            connection.close()

    def create_user(self, username: str, password_hash: str):
        statement = (
            "INSERT INTO users (username, password_hash) VALUES (?, ?) RETURNING id, username, created_at"
            if self.is_sqlite
            else "INSERT INTO users (username, password_hash) VALUES (%s, %s) RETURNING id, username, created_at"
        )

        try:
            with self.connection() as connection:
                cursor = connection.cursor()
                cursor.execute(statement, (username, password_hash))
                row = cursor.fetchone()
                connection.commit()
                return self._normalize_row(row)
        except sqlite3.IntegrityError as exc:
            raise ValueError("username already exists") from exc
        except Exception as exc:
            if psycopg is not None and isinstance(exc, psycopg.IntegrityError):
                raise ValueError("username already exists") from exc
            raise

    def get_user_by_username(self, username: str):
        statement = (
            "SELECT id, username, password_hash, created_at FROM users WHERE username = ?"
            if self.is_sqlite
            else "SELECT id, username, password_hash, created_at FROM users WHERE username = %s"
        )
        with self.connection() as connection:
            cursor = connection.cursor()
            cursor.execute(statement, (username,))
            row = cursor.fetchone()
            return self._normalize_row(row) if row else None

    def _normalize_row(self, row):
        if row is None:
            return None
        if isinstance(row, sqlite3.Row):
            return dict(row)
        return row

    def _sqlite_path(self) -> str:
        path = self.parsed_url.path or "./zlinebot.db"
        if path == ":memory:":
            return path
        if path.startswith("/") and self.database_url.startswith("sqlite:///"):
            return path
        return path.lstrip("/")

    def _schema_statements(self) -> list[str]:
        if self.is_sqlite:
            return [
                """
                CREATE TABLE IF NOT EXISTS users (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  username TEXT UNIQUE NOT NULL,
                  password_hash TEXT NOT NULL,
                  role TEXT NOT NULL DEFAULT 'user',
                  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            ]

        return [
            """
            CREATE TABLE IF NOT EXISTS users (
              id SERIAL PRIMARY KEY,
              username TEXT UNIQUE NOT NULL,
              password_hash TEXT,
              role TEXT NOT NULL DEFAULT 'user',
              created_at TIMESTAMPTZ DEFAULT NOW()
            )
            """,
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT",
            """
            DO $$
            BEGIN
              IF EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_name = 'users' AND column_name = 'password'
              ) THEN
                EXECUTE 'UPDATE users SET password_hash = password WHERE password_hash IS NULL AND password IS NOT NULL';
              END IF;
            END $$;
            """,
        ]


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1)
    return "scrypt$16384$8$1${}${}".format(
        base64.b64encode(salt).decode("utf-8"),
        base64.b64encode(digest).decode("utf-8"),
    )



def verify_password(password: str, encoded_hash: str) -> bool:
    try:
        _, n_value, r_value, p_value, salt_b64, digest_b64 = encoded_hash.split("$", 5)
        salt = base64.b64decode(salt_b64.encode("utf-8"))
        expected = base64.b64decode(digest_b64.encode("utf-8"))
        actual = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(n_value),
            r=int(r_value),
            p=int(p_value),
        )
    except (AttributeError, ValueError, TypeError, binascii.Error):
        return False

    return hmac.compare_digest(actual, expected)



def _health_payload():
    return {"status": "ok", "service": "api"}



def create_app(database_url: str | None = None) -> FastAPI:
    user_store = UserStore(database_url or DEFAULT_DATABASE_URL)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.user_store.initialize()
        yield

    app = FastAPI(title="zLineBot-automos API", lifespan=lifespan)
    app.state.user_store = user_store
    if user_store.is_sqlite:
        user_store.initialize()

    @app.get("/health")
    def health():
        return _health_payload()

    @app.get("/api/health")
    def health_api():
        return _health_payload()

    @app.post("/api/register")
    def register(payload: AuthPayload):
        username = payload.username.strip()
        password = payload.password

        if len(username) < 3:
            raise HTTPException(status_code=400, detail="username too short")
        if len(password) < 8:
            raise HTTPException(status_code=400, detail="password must be at least 8 characters")

        try:
            user = app.state.user_store.create_user(username, hash_password(password))
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

        return {
            "ok": True,
            "user": {
                "id": user["id"],
                "username": user["username"],
                "created_at": str(user["created_at"]),
            },
        }

    @app.post("/api/login")
    def login(payload: AuthPayload):
        username = payload.username.strip()
        password = payload.password

        if not username or not password:
            raise HTTPException(status_code=400, detail="invalid credentials")

        user = app.state.user_store.get_user_by_username(username)
        if user is None or not verify_password(password, user["password_hash"]):
            raise HTTPException(status_code=401, detail="invalid credentials")

        exp = datetime.now(tz=timezone.utc) + timedelta(hours=12)
        token = jwt.encode({"sub": user["username"], "exp": exp}, JWT_SECRET, algorithm=JWT_ALG)
        return {
            "access_token": token,
            "token_type": "bearer",
            "user": {"id": user["id"], "username": user["username"]},
        }

    @app.post("/api/chat")
    def chat(payload: ChatPayload):
        text = payload.message.strip()
        if not text:
            raise HTTPException(status_code=400, detail="message is required")
        return {"reply": f"Echo: {text}"}

    return app


app = create_app()
