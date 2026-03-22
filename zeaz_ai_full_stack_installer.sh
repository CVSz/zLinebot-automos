#!/usr/bin/env bash
# ZEAZ Ultimate SaaS V2 - Single-file installer
# Target: Ubuntu 24.04 VM (VMware 16GB RAM / 300GB NVMe)
# Installs: Docker stack (API, Worker, Postgres, Redis, Kafka, NGINX panels)
# Usage:
#   sudo bash zeaz_ai_full_stack_installer.sh --domain zeaz.local

set -euo pipefail

DOMAIN=""
CERT_EMAIL=""
APP_DIR="/opt/zeaz-v2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --cert-email) CERT_EMAIL="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: sudo bash zeaz_ai_full_stack_installer.sh --domain your-domain [--cert-email admin@your-domain]"
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "[1/8] Preflight checks"
free -g | awk '/Mem:/ {if ($2 < 8) {print "Need >=8GB RAM"; exit 1}}'
df -BG / | awk 'NR==2 {gsub("G","",$4); if ($4 < 50) {print "Need >=50GB free disk"; exit 1}}'

log "[2/8] Install dependencies"
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y docker.io docker-compose-plugin curl jq openssl ca-certificates ufw certbot
systemctl enable docker
systemctl start docker

log "[3/8] Generate project files"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"/{api,worker,analytics,infra,panels/{admin,user,devops},backup,monitor,logs,db,certs}

DB_PASS="$(openssl rand -hex 32)"
REDIS_PASS="$(openssl rand -hex 32)"
JWT_SECRET_CURRENT="$(openssl rand -hex 48)"
JWT_SECRET_PREVIOUS=""
KAFKA_USER="zeaz_app"
KAFKA_PASS="$(openssl rand -hex 24)"
ADMIN_PASS="$(openssl rand -base64 18)"

cat > "$APP_DIR/.env" <<ENVFILE
DOMAIN=${DOMAIN}
DB_PASS=${DB_PASS}
REDIS_PASS=${REDIS_PASS}
TRUST_PROXY=true
REAL_IP_HEADER=X-Forwarded-For
DATABASE_URL=postgresql://zeaz:${DB_PASS}@db:5432/zeaz
JWT_SECRET=${JWT_SECRET_CURRENT}
JWT_SECRET_CURRENT=${JWT_SECRET_CURRENT}
JWT_SECRET_PREVIOUS=${JWT_SECRET_PREVIOUS}
REDIS_URL=redis://:${REDIS_PASS}@redis:6379/0
KAFKA_BROKER=kafka:9092
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=PLAIN
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
ENVFILE
chmod 600 "$APP_DIR/.env"

cat > "$APP_DIR/api/api.env" <<ENVFILE
DATABASE_URL=postgresql://zeaz:${DB_PASS}@db:5432/zeaz
JWT_SECRET=${JWT_SECRET_CURRENT}
JWT_SECRET_CURRENT=${JWT_SECRET_CURRENT}
JWT_SECRET_PREVIOUS=${JWT_SECRET_PREVIOUS}
REDIS_URL=redis://:${REDIS_PASS}@redis:6379/0
TRUST_PROXY=true
REAL_IP_HEADER=X-Forwarded-For
KAFKA_BROKER=kafka:9092
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=PLAIN
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
CORS_ORIGINS=https://${DOMAIN}
OPENAI_API_KEY=REPLACE
OPENAI_MODEL=gpt-4.1-mini
QDRANT_HOST=qdrant
QDRANT_PORT=6333
MEMORY_MODEL=all-MiniLM-L6-v2
API_HMAC_SECRET=$(openssl rand -hex 48)
STRIPE_SECRET=REPLACE
ENVFILE
chmod 600 "$APP_DIR/api/api.env"

cat > "$APP_DIR/worker/worker.env" <<ENVFILE
DATABASE_URL=postgresql://zeaz:${DB_PASS}@db:5432/zeaz
KAFKA_BROKER=kafka:9092
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=PLAIN
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
ENVFILE
chmod 600 "$APP_DIR/worker/worker.env"

if [[ -n "$CERT_EMAIL" && "$DOMAIN" != "localhost" && "$DOMAIN" != *.local ]]; then
  log "Attempting Let's Encrypt certificate for ${DOMAIN}"
  OCCUPYING_CONTAINERS="$(docker ps --filter publish=80 --format '{{.ID}}')"
  if [[ -n "${OCCUPYING_CONTAINERS}" ]]; then
    log "Stopping containers bound to port 80 for certbot standalone challenge"
    docker stop ${OCCUPYING_CONTAINERS} >/dev/null
  fi
  if certbot certonly --standalone --non-interactive --agree-tos -m "$CERT_EMAIL" -d "$DOMAIN"; then
    cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "$APP_DIR/certs/tls.crt"
    cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "$APP_DIR/certs/tls.key"
    chmod 600 "$APP_DIR/certs/tls.key"
    log "Let's Encrypt certificate issued for ${DOMAIN}"
  else
    log "Let's Encrypt failed, falling back to self-signed certificate"
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout "$APP_DIR/certs/tls.key" \
      -out "$APP_DIR/certs/tls.crt" \
      -days 365 \
      -subj "/CN=${DOMAIN}"
    chmod 600 "$APP_DIR/certs/tls.key"
  fi
else
  log "Using self-signed certificate (provide --cert-email for Let's Encrypt on public domains)"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$APP_DIR/certs/tls.key" \
    -out "$APP_DIR/certs/tls.crt" \
    -days 365 \
    -subj "/CN=${DOMAIN}"
  chmod 600 "$APP_DIR/certs/tls.key"
fi

cat > "$APP_DIR/db/init.sql" <<SQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users(
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  tenant_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tenants(
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  plan TEXT NOT NULL DEFAULT 'free',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages(
  id BIGSERIAL PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_tenant ON messages(tenant_id);

CREATE TABLE IF NOT EXISTS audit_logs(
  id BIGSERIAL PRIMARY KEY,
  username TEXT,
  event_type TEXT NOT NULL,
  source_ip TEXT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);

CREATE TABLE IF NOT EXISTS api_keys (
  id BIGSERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  owner TEXT NOT NULL,
  quota INT NOT NULL DEFAULT 10000,
  used INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS subscriptions (
  user_id TEXT PRIMARY KEY,
  plan TEXT NOT NULL DEFAULT 'free',
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS apps (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  owner TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO users(username,password,role)
VALUES('admin', crypt('${ADMIN_PASS}', gen_salt('bf', 12)), 'admin')
ON CONFLICT (username) DO NOTHING;
SQL

cat > "$APP_DIR/api/requirements.txt" <<'REQ'
fastapi==0.110.0
uvicorn==0.29.0
sqlalchemy==2.0.29
psycopg2-binary==2.9.9
python-jose==3.3.0
passlib[bcrypt]==1.7.4
redis==5.0.1
kafka-python==2.0.2
openai==1.14.0
pydantic==2.6.4
backoff==2.2.1
stripe==9.2.0
qdrant-client==1.9.0
sentence-transformers==2.7.0
httpx==0.27.0
REQ

cat > "$APP_DIR/api/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
RUN useradd -m -u 10001 appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER appuser
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000","--timeout-keep-alive","5"]
DOCKER

cat > "$APP_DIR/api/main.py" <<'PYCODE'
import os
import time
import json
import uuid
import hmac
import hashlib
from threading import Lock
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException, Depends, Header, Security, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from jose import jwt, JWTError
from passlib.context import CryptContext
from kafka import KafkaProducer
from redis import Redis
from openai import OpenAI
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
from sentence_transformers import SentenceTransformer
import stripe

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
AI_ENABLED = OPENAI_API_KEY not in {"", "REPLACE"}
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
STRIPE_SECRET = os.getenv("STRIPE_SECRET", "")
QDRANT_HOST = os.getenv("QDRANT_HOST", "qdrant")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
MEMORY_MODEL = os.getenv("MEMORY_MODEL", "all-MiniLM-L6-v2")
MEMORY_COLLECTION = "memory"
API_HMAC_SECRET = os.getenv("API_HMAC_SECRET", "")
JWT_PRIMARY = os.getenv("JWT_SECRET_CURRENT") or os.getenv("JWT_SECRET", "")
JWT_FALLBACK = [k for k in os.getenv("JWT_SECRET_PREVIOUS", "").split(",") if k]
JWT_KEYS = [JWT_PRIMARY, *JWT_FALLBACK]
if not JWT_PRIMARY:
    raise RuntimeError("JWT secret is required")
DB = create_engine(
    os.getenv("DATABASE_URL"),
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    pool_timeout=10,
    pool_recycle=1800,
)
REDIS = Redis.from_url(os.getenv("REDIS_URL"), decode_responses=True)
pwd_context = CryptContext(schemes=["bcrypt"], bcrypt__rounds=12, deprecated="auto")
security = HTTPBearer(auto_error=False)
producer = KafkaProducer(
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    value_serializer=lambda v: json.dumps(v).encode(),
    retries=5,
    request_timeout_ms=5000,
    security_protocol=os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT"),
    sasl_mechanism=os.getenv("KAFKA_SASL_MECHANISM", "PLAIN"),
    sasl_plain_username=os.getenv("KAFKA_USERNAME"),
    sasl_plain_password=os.getenv("KAFKA_PASSWORD"),
)
openai_client = OpenAI(api_key=OPENAI_API_KEY) if AI_ENABLED else None
qdrant = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
memory_model = SentenceTransformer(MEMORY_MODEL)
if STRIPE_SECRET and STRIPE_SECRET != "REPLACE":
    stripe.api_key = STRIPE_SECRET


def safe_redis(fn, default=None):
    try:
        return fn()
    except Exception:
        return default


def wait_for_db(max_attempts: int = 10, sleep_seconds: int = 3) -> None:
    for attempt in range(1, max_attempts + 1):
        try:
            with DB.connect() as conn:
                conn.execute(text("SELECT 1"))
            return
        except Exception:
            if attempt == max_attempts:
                raise RuntimeError("DB not ready after retries")
            time.sleep(sleep_seconds)


wait_for_db()


def ensure_memory_collection() -> None:
    existing = [c.name for c in qdrant.get_collections().collections]
    if MEMORY_COLLECTION in existing:
        return
    qdrant.create_collection(
        collection_name=MEMORY_COLLECTION,
        vectors_config=VectorParams(size=384, distance=Distance.COSINE),
    )


def encode_text(text: str) -> list[float]:
    return memory_model.encode(text).tolist()


def store_memory(user: str, text_value: str):
    ensure_memory_collection()
    payload = {"user": user, "text": text_value}
    point = PointStruct(id=str(uuid.uuid4()), vector=encode_text(text_value), payload=payload)
    qdrant.upsert(collection_name=MEMORY_COLLECTION, points=[point])


def recall_memory(user: str, query: str, limit: int = 5) -> list[str]:
    ensure_memory_collection()
    hits = qdrant.search(
        collection_name=MEMORY_COLLECTION,
        query_vector=encode_text(query),
        query_filter={"must": [{"key": "user", "match": {"value": user}}]},
        limit=limit,
    )
    return [h.payload.get("text", "") for h in hits if h.payload and h.payload.get("text")]

class CircuitBreaker:
    def __init__(self, threshold=5):
        self.fail = 0
        self.threshold = threshold
        self.lock = Lock()

    def call(self, fn, *a, **kw):
        with self.lock:
            if self.fail >= self.threshold:
                raise HTTPException(503, "circuit_open")
        try:
            result = fn(*a, **kw)
            with self.lock:
                self.fail = 0
            return result
        except Exception:
            with self.lock:
                self.fail += 1
            raise

cb = CircuitBreaker()
app = FastAPI(title="ZEAZ SaaS API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in os.getenv("CORS_ORIGINS", "https://localhost").split(",") if o.strip()],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-API-Key"],
)

class UserIn(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=8, max_length=128)

class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)

class CheckoutIn(BaseModel):
    price_cents: int = Field(default=1000, ge=100, le=1000000)
    success_url: str = Field(min_length=8, max_length=500)
    cancel_url: str = Field(min_length=8, max_length=500)

class AgentTaskIn(BaseModel):
    task: str = Field(min_length=3, max_length=500)


def check_plan(user: str) -> str:
    with DB.begin() as conn:
        row = conn.execute(
            text(
                """
                SELECT plan FROM subscriptions
                WHERE user_id=:u AND status='active'
                AND (expires_at IS NULL OR expires_at > NOW())
                """
            ),
            {"u": user},
        ).fetchone()
    return row[0] if row else "free"


def verify_hmac_signature(request: Request, body_bytes: bytes, x_timestamp: str, x_signature: str):
    if not API_HMAC_SECRET:
        return
    if not x_timestamp or not x_signature:
        raise HTTPException(401, "missing_signature")
    signed = f"{x_timestamp}.{body_bytes.decode('utf-8', errors='ignore')}".encode()
    expected = hmac.new(API_HMAC_SECRET.encode(), signed, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, x_signature):
        raise HTTPException(401, "invalid_signature")


def issue_access_token(username: str, role: str) -> str:
    payload = {
        "sub": username,
        "role": role,
        "exp": datetime.now(timezone.utc) + timedelta(hours=1),
        "typ": "access",
    }
    return jwt.encode(payload, JWT_PRIMARY, algorithm="HS256")


def issue_refresh_token(username: str, role: str) -> str:
    token = os.urandom(48).hex()
    if not safe_redis(lambda: REDIS.setex(f"rt:{token}", 7 * 24 * 3600, json.dumps({"sub": username, "role": role})), False):
        raise HTTPException(503, "token_store_unavailable")
    safe_redis(lambda: REDIS.sadd(f"rt_user:{username}", token))
    safe_redis(lambda: REDIS.expire(f"rt_user:{username}", 7 * 24 * 3600))
    return token


def authz(credentials: HTTPAuthorizationCredentials = Security(security)):
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(401, "missing_token")
    for key in JWT_KEYS:
        try:
            return jwt.decode(credentials.credentials, key, algorithms=["HS256"])
        except JWTError:
            continue
    raise HTTPException(401, "invalid_token")


def check_rate_limit(subject: str):
    key = f"rl:{subject}:{int(time.time() / 60)}"
    count = safe_redis(lambda: REDIS.incr(key), 1)
    if count == 1:
        safe_redis(lambda: REDIS.expire(key, 60))
    if count > 120:
        raise HTTPException(429, "rate_limited")


def apply_login_delay(username: str, source_ip: str):
    key = f"lf:{username}:{source_ip}"
    attempts = safe_redis(lambda: REDIS.incr(key), 1)
    if attempts == 1:
        safe_redis(lambda: REDIS.expire(key, 900))
    delay = min(5, max(0, attempts - 1))
    if delay:
        time.sleep(delay)


def clear_login_delay(username: str, source_ip: str):
    safe_redis(lambda: REDIS.delete(f"lf:{username}:{source_ip}"))


def write_audit(event_type: str, username: str = "", source_ip: str = "", details: dict | None = None):
    payload = details or {}
    with DB.begin() as conn:
        conn.execute(
            text("INSERT INTO audit_logs(username,event_type,source_ip,details) VALUES(:u,:e,:ip,:d::jsonb)"),
            {"u": username or None, "e": event_type, "ip": source_ip or None, "d": json.dumps(payload)},
        )


def noop_ai(message: str) -> str:
    if not AI_ENABLED:
        return "AI not configured"
    response = openai_client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[{"role": "user", "content": message}],
        timeout=10,
    )
    content = response.choices[0].message.content if response.choices else ""
    return (content or "").strip()[:4000] or "No response"


def ensure_tenant(username: str) -> str:
    tenant_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, username))
    with DB.begin() as conn:
        conn.execute(
            text("INSERT INTO tenants(id,name) VALUES(:id,:name) ON CONFLICT (id) DO NOTHING"),
            {"id": tenant_id, "name": username},
        )
        conn.execute(
            text("UPDATE users SET tenant_id=:tid WHERE username=:u AND tenant_id IS NULL"),
            {"tid": tenant_id, "u": username},
        )
    return tenant_id


def validate_api_key(x_api_key: str) -> str | None:
    if not x_api_key:
        return None
    with DB.begin() as conn:
        row = conn.execute(
            text("SELECT owner, quota, used FROM api_keys WHERE key=:k"),
            {"k": x_api_key},
        ).fetchone()
        if not row:
            raise HTTPException(403, "invalid_api_key")
        if row[2] >= row[1]:
            raise HTTPException(402, "quota_exceeded")
        conn.execute(text("UPDATE api_keys SET used=used+1 WHERE key=:k"), {"k": x_api_key})
    return row[0]


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/register")
def register(user: UserIn):
    try:
        with DB.begin() as conn:
            conn.execute(
                text("INSERT INTO users(username,password,role) VALUES(:u,:p,'user')"),
                {"u": user.username, "p": pwd_context.hash(user.password)}
            )
    except IntegrityError:
        raise HTTPException(409, "username_exists")
    return {"ok": True}


@app.post("/login")
def login(user: UserIn, x_forwarded_for: str = Header(default="")):
    source_ip = (x_forwarded_for.split(",")[0].strip() if x_forwarded_for else "unknown")
    check_rate_limit(f"login-ip:{source_ip}")
    check_rate_limit(f"login-user:{user.username}")
    apply_login_delay(user.username, source_ip)
    with DB.begin() as conn:
        row = conn.execute(text("SELECT password, role FROM users WHERE username=:u"), {"u": user.username}).fetchone()
    if not row or not pwd_context.verify(user.password, row[0]):
        write_audit("login_failed", username=user.username, source_ip=source_ip)
        raise HTTPException(401, "invalid_credentials")
    ensure_tenant(user.username)
    clear_login_delay(user.username, source_ip)
    write_audit("login_success", username=user.username, source_ip=source_ip)
    return {
        "token": issue_access_token(user.username, row[1]),
        "refresh_token": issue_refresh_token(user.username, row[1]),
    }


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=64, max_length=256)


@app.post("/refresh")
def refresh(body: RefreshIn):
    key = f"rt:{body.refresh_token}"
    redis_failed = object()
    raw = safe_redis(lambda: REDIS.get(key), redis_failed)
    if raw is redis_failed:
        raise HTTPException(503, "token_store_unavailable")
    if not raw:
        raise HTTPException(401, "invalid_refresh_token")
    claims = json.loads(raw)
    safe_redis(lambda: REDIS.delete(key))
    safe_redis(lambda: REDIS.srem(f"rt_user:{claims['sub']}", body.refresh_token))
    write_audit("token_refresh", username=claims["sub"])
    return {
        "token": issue_access_token(claims["sub"], claims["role"]),
        "refresh_token": issue_refresh_token(claims["sub"], claims["role"]),
    }


@app.post("/logout")
def logout(body: RefreshIn):
    key = f"rt:{body.refresh_token}"
    redis_failed = object()
    raw = safe_redis(lambda: REDIS.get(key), redis_failed)
    if raw is redis_failed:
        return {"ok": True, "degraded": True}
    if not raw:
        return {"ok": True}
    claims = json.loads(raw)
    safe_redis(lambda: REDIS.delete(key))
    safe_redis(lambda: REDIS.srem(f"rt_user:{claims['sub']}", body.refresh_token))
    write_audit("logout", username=claims["sub"])
    return {"ok": True}


@app.post("/logout_all")
def logout_all(claims=Depends(authz)):
    tokens_key = f"rt_user:{claims['sub']}"
    tokens = safe_redis(lambda: REDIS.smembers(tokens_key), set())
    if tokens:
        pipeline = REDIS.pipeline()
        for token in tokens:
            pipeline.delete(f"rt:{token}")
        pipeline.delete(tokens_key)
        safe_redis(lambda: pipeline.execute())
    write_audit("logout_all", username=claims["sub"])
    return {"ok": True, "revoked": len(tokens)}


@app.post("/chat")
async def chat(
    req: ChatIn,
    request: Request,
    claims=Depends(authz),
    x_api_key: str = Header(default=""),
    x_signature: str = Header(default=""),
    x_timestamp: str = Header(default=""),
):
    check_rate_limit(claims["sub"])
    verify_hmac_signature(request, await request.body(), x_timestamp, x_signature)
    owner = validate_api_key(x_api_key)
    plan = check_plan(claims["sub"])
    if plan == "free":
        raise HTTPException(402, "upgrade_required")
    tenant_id = ensure_tenant(claims["sub"])
    memories = recall_memory(claims["sub"], req.message)
    context = "\n".join(memories)
    prompt = req.message if not context else f"Context:\n{context}\n\nUser request:\n{req.message}"
    reply = cb.call(noop_ai, prompt)
    store_memory(claims["sub"], req.message)
    try:
        producer.send(
            "events.messages",
            key=claims["sub"].encode(),
            value={"tenant": claims["sub"], "tenant_id": tenant_id, "msg": req.message},
        ).get(timeout=5)
    except Exception:
        write_audit("kafka_failed", username=claims["sub"], details={"event": "events.messages"})
    write_audit("chat_used", username=claims["sub"], details={"message_len": len(req.message), "api_key_owner": owner})
    return {
        "reply": reply,
        "x_api_key_seen": bool(x_api_key),
        "api_key_owner": owner,
        "plan": plan,
        "memory_hits": len(memories),
    }


@app.get("/market/{app_name}")
def call_market_app(app_name: str, claims=Depends(authz)):
    with DB.begin() as conn:
        row = conn.execute(
            text("SELECT endpoint, owner FROM apps WHERE name=:n"),
            {"n": app_name},
        ).fetchone()
    if not row:
        raise HTTPException(404, "app_not_found")
    endpoint, owner = row[0], row[1]
    try:
        response = httpx.get(endpoint, timeout=10)
        return {
            "app": app_name,
            "owner": owner,
            "status_code": response.status_code,
            "response": response.text[:2000],
        }
    except Exception:
        raise HTTPException(502, "app_unreachable")


@app.post("/create-checkout")
def create_checkout(body: CheckoutIn, claims=Depends(authz)):
    if not STRIPE_SECRET or STRIPE_SECRET == "REPLACE":
        raise HTTPException(503, "stripe_not_configured")
    session = stripe.checkout.Session.create(
        payment_method_types=["card"],
        line_items=[{
            "price_data": {
                "currency": "usd",
                "product_data": {"name": "ZEAZ API Plan"},
                "unit_amount": body.price_cents,
            },
            "quantity": 1,
        }],
        mode="payment",
        success_url=body.success_url,
        cancel_url=body.cancel_url,
        metadata={"user": claims["sub"]},
    )
    try:
        producer.send(
            "events.billing",
            key=claims["sub"].encode(),
            value={"user": claims["sub"], "session_id": session.id, "amount": body.price_cents},
        ).get(timeout=5)
    except Exception:
        write_audit("kafka_failed", username=claims["sub"], details={"event": "events.billing"})
    return {"url": session.url, "id": session.id}


@app.post("/agent/task")
def create_agent_task(body: AgentTaskIn, claims=Depends(authz)):
    tenant_id = ensure_tenant(claims["sub"])
    producer.send(
        "events.agent.tasks",
        key=claims["sub"].encode(),
        value={"user": claims["sub"], "tenant_id": tenant_id, "task": body.task},
    ).get(timeout=5)
    return {"queued": True}


@app.get("/metrics")
def metrics(claims=Depends(authz)):
    if claims.get("role") != "admin":
        raise HTTPException(403, "admin_only")
    write_audit("admin_metrics_access", username=claims.get("sub", ""))
    return {"users": "restricted"}
PYCODE

cat > "$APP_DIR/worker/requirements.txt" <<'REQ'
kafka-python==2.0.2
sqlalchemy==2.0.29
psycopg2-binary==2.9.9
REQ

cat > "$APP_DIR/worker/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
RUN useradd -m -u 10001 appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER appuser
CMD ["python","worker.py"]
DOCKER

cat > "$APP_DIR/worker/worker.py" <<'PYCODE'
import os
import json
import time

from kafka import KafkaConsumer, KafkaProducer
from sqlalchemy import create_engine, text

DB = create_engine(os.getenv("DATABASE_URL"), pool_pre_ping=True)
producer = KafkaProducer(
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    value_serializer=lambda v: json.dumps(v).encode(),
    retries=5,
    request_timeout_ms=5000,
    security_protocol=os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT"),
    sasl_mechanism=os.getenv("KAFKA_SASL_MECHANISM", "PLAIN"),
    sasl_plain_username=os.getenv("KAFKA_USERNAME"),
    sasl_plain_password=os.getenv("KAFKA_PASSWORD"),
)
consumer = KafkaConsumer(
    "events.messages",
    "events.agent.tasks",
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    enable_auto_commit=False,
    value_deserializer=lambda m: json.loads(m.decode()),
    security_protocol=os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT"),
    sasl_mechanism=os.getenv("KAFKA_SASL_MECHANISM", "PLAIN"),
    sasl_plain_username=os.getenv("KAFKA_USERNAME"),
    sasl_plain_password=os.getenv("KAFKA_PASSWORD"),
)


def wait_for_db(max_attempts: int = 10, sleep_seconds: int = 3) -> None:
    for attempt in range(1, max_attempts + 1):
        try:
            with DB.connect() as conn:
                conn.execute(text("SELECT 1"))
            return
        except Exception:
            if attempt == max_attempts:
                raise RuntimeError("DB not ready after retries")
            time.sleep(sleep_seconds)


wait_for_db()

for msg in consumer:
    try:
        topic = msg.topic
        with DB.begin() as conn:
            if topic == "events.messages":
                tenant_id = str(msg.value.get("tenant_id", "")).strip()
                if not tenant_id:
                    raise ValueError("missing tenant_id")
                conn.execute(
                    text("INSERT INTO messages(tenant_id,content) VALUES(:t,:c)"),
                    {"t": tenant_id, "c": msg.value.get("msg", "")},
                )
            elif topic == "events.agent.tasks":
                tenant_id = str(msg.value.get("tenant_id", "")).strip()
                task = str(msg.value.get("task", "")).strip()
                if not tenant_id or not task:
                    raise ValueError("missing agent task payload")
                conn.execute(
                    text("INSERT INTO messages(tenant_id,content) VALUES(:t,:c)"),
                    {"t": tenant_id, "c": f"[agent_result] completed task: {task}"},
                )
        consumer.commit()
    except Exception:
        try:
            producer.send("events.dlq", msg.value).get(timeout=5)
        except Exception:
            pass
        time.sleep(1)
PYCODE

cat > "$APP_DIR/panels/admin/index.html" <<'HTML'
<!doctype html><html><body><h1>Admin Panel</h1><p>Use API /api/login then call admin APIs with Bearer token.</p></body></html>
HTML
cat > "$APP_DIR/panels/user/index.html" <<'HTML'
<!doctype html><html><body><h1>User Panel</h1><p>Use /api/register and /api/login first.</p></body></html>
HTML
cat > "$APP_DIR/panels/devops/index.html" <<'HTML'
<!doctype html><html><body><h1>DevOps Panel</h1><p>Metrics require admin token; endpoint is proxied at /api/metrics.</p></body></html>
HTML

cat > "$APP_DIR/analytics/requirements.txt" <<'REQ'
kafka-python==2.0.2
httpx==0.27.0
REQ

cat > "$APP_DIR/analytics/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
RUN useradd -m -u 10001 appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER appuser
CMD ["python","analytics_worker.py"]
DOCKER

cat > "$APP_DIR/analytics/analytics_worker.py" <<'PYCODE'
import os
import json
import time

import httpx
from kafka import KafkaConsumer

CLICKHOUSE_URL = os.getenv("CLICKHOUSE_URL", "http://clickhouse:8123")
consumer = KafkaConsumer(
    "events.analytics",
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    enable_auto_commit=False,
    value_deserializer=lambda m: json.loads(m.decode()),
    security_protocol=os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT"),
    sasl_mechanism=os.getenv("KAFKA_SASL_MECHANISM", "PLAIN"),
    sasl_plain_username=os.getenv("KAFKA_USERNAME"),
    sasl_plain_password=os.getenv("KAFKA_PASSWORD"),
)

with httpx.Client(timeout=10) as client:
    for msg in consumer:
        event = msg.value
        try:
            payload = (
                "INSERT INTO events (event_json, created_at) FORMAT JSONEachRow\n"
                + json.dumps({"event_json": json.dumps(event), "created_at": time.strftime("%Y-%m-%d %H:%M:%S")})
            )
            client.post(f"{CLICKHOUSE_URL}/?database=default", content=payload)
            consumer.commit()
        except Exception:
            time.sleep(1)
PYCODE

cat > "$APP_DIR/infra/nginx.conf" <<'NGINX'
events {}
http {
  limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
  limit_req_zone $binary_remote_addr zone=global_limit:10m rate=30r/s;
  limit_conn_zone $binary_remote_addr zone=perip:10m;
  gzip on;
  gzip_types text/plain text/css application/json application/javascript application/xml+rss;
  client_max_body_size 1m;
  real_ip_header X-Forwarded-For;
  set_real_ip_from 0.0.0.0/0;

  server {
    listen 80;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl;
    ssl_certificate /etc/nginx/certs/tls.crt;
    ssl_certificate_key /etc/nginx/certs/tls.key;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; connect-src 'self' https:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=()" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    limit_conn perip 30;

    location /api/ {
      limit_req zone=global_limit burst=50 nodelay;
      limit_req zone=api_limit burst=20 nodelay;
      proxy_pass http://api:8000;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /admin/ {
      alias /usr/share/nginx/html/admin/;
    }

    location /user/ {
      alias /usr/share/nginx/html/user/;
    }

    location /devops/ {
      alias /usr/share/nginx/html/devops/;
    }
  }
}
NGINX

cat > "$APP_DIR/infra/nginx.Dockerfile" <<'DOCKER'
FROM nginx:alpine
COPY infra/nginx.conf /etc/nginx/nginx.conf
COPY certs /etc/nginx/certs
COPY panels/admin /usr/share/nginx/html/admin
COPY panels/user /usr/share/nginx/html/user
COPY panels/devops /usr/share/nginx/html/devops
DOCKER

cat > "$APP_DIR/infra/docker-compose.yml" <<COMPOSE
services:
  api:
    build: ../api
    env_file: ../api/api.env
    restart: always
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
      kafka:
        condition: service_healthy
      qdrant:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    read_only: true
    tmpfs:
      - /tmp
      - /app/logs
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  worker:
    build: ../worker
    env_file: ../worker/worker.env
    restart: always
    depends_on:
      db:
        condition: service_healthy
      kafka:
        condition: service_healthy
    read_only: true
    tmpfs:
      - /tmp
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  analytics_worker:
    build: ../analytics
    env_file: ../worker/worker.env
    environment:
      CLICKHOUSE_URL: http://clickhouse:8123
    restart: always
    depends_on:
      kafka:
        condition: service_healthy
      clickhouse:
        condition: service_started
    read_only: true
    tmpfs:
      - /tmp
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    mem_limit: 512m
    cpus: 0.5
    networks: [internal]

  db:
    image: postgres:15
    restart: always
    command: ["postgres", "-c", "max_connections=100"]
    environment:
      POSTGRES_DB: zeaz
      POSTGRES_USER: zeaz
      POSTGRES_PASSWORD: ${DB_PASS}
    volumes:
      - db_data:/var/lib/postgresql/data
      - ../db/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U zeaz -d zeaz"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  redis:
    image: redis:7
    restart: always
    command: ["redis-server","--requirepass","${REDIS_PASS}","--appendonly","yes","--bind","0.0.0.0","--protected-mode","no"]
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASS}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 512m
    cpus: 0.5
    networks: [internal]

  qdrant:
    image: qdrant/qdrant:latest
    restart: always
    volumes:
      - qdrant_data:/qdrant/storage
    ports:
      - "6333:6333"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  zookeeper:
    image: bitnami/zookeeper:latest
    restart: always
    environment:
      ALLOW_ANONYMOUS_LOGIN: "no"
      ZOO_ENABLE_AUTH: "yes"
      ZOO_SERVER_USERS: ${KAFKA_USER}
      ZOO_SERVER_PASSWORDS: ${KAFKA_PASS}
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 512m
    cpus: 0.5
    networks: [internal]

  kafka:
    image: bitnami/kafka:latest
    restart: always
    depends_on: [zookeeper]
    volumes:
      - kafka_data:/bitnami/kafka
    environment:
      KAFKA_CFG_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ZOOKEEPER_PROTOCOL: SASL
      KAFKA_ZOOKEEPER_USER: ${KAFKA_USER}
      KAFKA_ZOOKEEPER_PASSWORD: ${KAFKA_PASS}
      KAFKA_CFG_LISTENERS: SASL_PLAINTEXT://:9092
      KAFKA_CFG_ADVERTISED_LISTENERS: SASL_PLAINTEXT://kafka:9092
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: SASL_PLAINTEXT:SASL_PLAINTEXT
      KAFKA_CFG_INTER_BROKER_LISTENER_NAME: SASL_PLAINTEXT
      KAFKA_CFG_SASL_ENABLED_MECHANISMS: PLAIN
      KAFKA_CFG_SASL_MECHANISM_INTER_BROKER_PROTOCOL: PLAIN
      KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_CLIENT_USERS: ${KAFKA_USER}
      KAFKA_CLIENT_PASSWORDS: ${KAFKA_PASS}
      KAFKA_CFG_LOG_RETENTION_HOURS: 168
    healthcheck:
      test: ["CMD-SHELL", "kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null 2>&1"]
      interval: 15s
      timeout: 10s
      retries: 10
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  clickhouse:
    image: clickhouse/clickhouse-server:latest
    restart: always
    environment:
      CLICKHOUSE_DB: default
    volumes:
      - clickhouse_data:/var/lib/clickhouse
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 1g
    cpus: 1.0
    networks: [internal]

  nginx:
    build:
      context: ..
      dockerfile: infra/nginx.Dockerfile
    restart: always
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost"]
      interval: 30s
      timeout: 5s
      retries: 3
    read_only: true
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    mem_limit: 256m
    cpus: 0.5
    networks: [internal, public]

volumes:
  db_data:
  redis_data:
  kafka_data:
  qdrant_data:
  clickhouse_data:

networks:
  internal:
    internal: true
  public:
COMPOSE

cat > "$APP_DIR/backup/backup.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%F_%H-%M)
FILE="/opt/zeaz-v2/backup/db_${TS}.sql.gz"
ENCRYPTED_FILE="${FILE}.enc"
BACKUP_KEY_FILE="/opt/zeaz-v2/backup/.backup_key"
DB_CONTAINER=$(docker compose -f /opt/zeaz-v2/infra/docker-compose.yml ps -q db)
docker exec "$DB_CONTAINER" pg_dump -U zeaz zeaz | gzip > "$FILE"
test -s "$FILE"
if [[ ! -f "$BACKUP_KEY_FILE" ]]; then
  umask 077
  openssl rand -hex 32 > "$BACKUP_KEY_FILE"
fi
openssl enc -aes-256-cbc -pbkdf2 -salt -in "$FILE" -out "$ENCRYPTED_FILE" -pass "file:${BACKUP_KEY_FILE}"
rm -f "$FILE"
test -s "$ENCRYPTED_FILE"
openssl enc -d -aes-256-cbc -pbkdf2 -in "$ENCRYPTED_FILE" -pass "file:${BACKUP_KEY_FILE}" | gunzip -c | head >/dev/null
find /opt/zeaz-v2/backup -type f -mtime +7 -delete
BASH
chmod +x "$APP_DIR/backup/backup.sh"

cat > "$APP_DIR/monitor/health.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
curl -fs http://localhost/ >/dev/null || echo "ALERT: nginx down"
curl -kfs https://localhost/ >/dev/null || echo "ALERT: nginx down (https)"
BASH
chmod +x "$APP_DIR/monitor/health.sh"

log "[4/8] Start stack"
cd "$APP_DIR/infra"
cp "$APP_DIR/.env" "$APP_DIR/infra/.env"
docker compose up -d --build
log "Waiting for DB..."
until docker compose exec -T db pg_isready -U zeaz -d zeaz >/dev/null 2>&1; do
  sleep 2
done

log "Waiting for Kafka..."
until docker compose exec -T kafka kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null 2>&1; do
  sleep 3
done

log "Creating Kafka topics..."
for i in {1..10}; do
  docker compose exec -T kafka kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null 2>&1 && break
  sleep 3
done
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.messages \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.billing \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.analytics \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.agent.tasks \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.security \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1
docker compose exec -T kafka kafka-topics.sh --create --if-not-exists --topic events.dlq \
  --bootstrap-server kafka:9092 --partitions 3 --replication-factor 1

log "Preparing ClickHouse events table..."
docker compose exec -T clickhouse clickhouse-client --query "
CREATE TABLE IF NOT EXISTS default.events (
  event_json String,
  created_at DateTime
) ENGINE = MergeTree
ORDER BY created_at
"

log "[5/8] Setup firewall and cron"
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force limit 22/tcp
ufw --force limit 80/tcp
ufw --force limit 443/tcp
ufw --force enable

(crontab -l 2>/dev/null; echo "0 3 * * * ${APP_DIR}/backup/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * ${APP_DIR}/monitor/health.sh") | crontab -

cat > /etc/logrotate.d/zeaz <<EOF
${APP_DIR}/logs/*.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
}
EOF

cat > /etc/systemd/system/zeaz.service <<EOF
[Unit]
Description=ZEAZ Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${APP_DIR}/infra
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable zeaz

if [[ -n "$CERT_EMAIL" && "$DOMAIN" != "localhost" && "$DOMAIN" != *.local ]]; then
  (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet && docker compose -f ${APP_DIR}/infra/docker-compose.yml restart nginx") | crontab -
fi

log "[6/8] Completed"
cat <<MSG
Installed at: ${APP_DIR}
URL: https://${DOMAIN}
Panels:
  - https://${DOMAIN}/admin/
  - https://${DOMAIN}/user/
  - https://${DOMAIN}/devops/
API:
  - POST /api/register
  - POST /api/login
  - POST /api/chat (Bearer token)
NOTE: Update OPENAI_API_KEY in ${APP_DIR}/api/api.env before production usage.
NOTE: API will still start without OPENAI_API_KEY and return "AI not configured" for chat responses.
NOTE: For trusted TLS, rerun with --cert-email admin@your-domain on a publicly-resolvable domain.
NOTE: Bootstrap admin user is created with username 'admin' and generated password '${ADMIN_PASS}' (rotate immediately).
API-specific secrets: ${APP_DIR}/api/api.env
Worker-specific secrets: ${APP_DIR}/worker/worker.env
MSG
