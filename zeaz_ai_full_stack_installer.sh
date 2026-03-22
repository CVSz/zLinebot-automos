#!/usr/bin/env bash
# ZEAZ Ultimate SaaS V2 - Single-file installer
# Target: Ubuntu 24.04 VM (VMware 16GB RAM / 300GB NVMe)
# Installs: Docker stack (API, Worker, Postgres, Redis, Kafka, NGINX panels)
# Usage:
#   sudo bash zeaz_ai_full_stack_installer.sh --domain zeaz.local

set -euo pipefail

DOMAIN=""
APP_DIR="/opt/zeaz-v2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: sudo bash zeaz_ai_full_stack_installer.sh --domain your-domain"
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
apt install -y docker.io docker-compose-plugin curl jq openssl ca-certificates ufw
systemctl enable docker
systemctl start docker

log "[3/8] Generate project files"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"/{api,worker,infra,panels/{admin,user,devops},backup,monitor,logs,db,certs}

DB_PASS="$(openssl rand -hex 32)"
REDIS_PASS="$(openssl rand -hex 32)"
JWT_SECRET_CURRENT="$(openssl rand -hex 48)"
JWT_SECRET_PREVIOUS=""
KAFKA_USER="zeaz_app"
KAFKA_PASS="$(openssl rand -hex 24)"

cat > "$APP_DIR/.env" <<ENVFILE
DOMAIN=${DOMAIN}
DB_PASS=${DB_PASS}
REDIS_PASS=${REDIS_PASS}
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
KAFKA_BROKER=kafka:9092
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=PLAIN
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
OPENAI_API_KEY=REPLACE
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

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$APP_DIR/certs/tls.key" \
  -out "$APP_DIR/certs/tls.crt" \
  -days 365 \
  -subj "/CN=${DOMAIN}"
chmod 600 "$APP_DIR/certs/tls.key"

cat > "$APP_DIR/db/init.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS users(
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
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
from threading import Lock
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, HTTPException, Depends, Header, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from jose import jwt, JWTError
from passlib.context import CryptContext
from kafka import KafkaProducer
from redis import Redis

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
JWT_PRIMARY = os.getenv("JWT_SECRET_CURRENT") or os.getenv("JWT_SECRET", "")
JWT_FALLBACK = [k for k in os.getenv("JWT_SECRET_PREVIOUS", "").split(",") if k]
JWT_KEYS = [JWT_PRIMARY, *JWT_FALLBACK]
if not JWT_PRIMARY:
    raise RuntimeError("JWT secret is required")
if OPENAI_API_KEY in {"", "REPLACE"}:
    raise RuntimeError("OPENAI_API_KEY must be set to a real key before startup")
DB = create_engine(
    os.getenv("DATABASE_URL"),
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,
    pool_recycle=1800,
)
REDIS = Redis.from_url(os.getenv("REDIS_URL"), decode_responses=True)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
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
    REDIS.setex(f"rt:{token}", 7 * 24 * 3600, json.dumps({"sub": username, "role": role}))
    REDIS.sadd(f"rt_user:{username}", token)
    REDIS.expire(f"rt_user:{username}", 7 * 24 * 3600)
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
    count = REDIS.incr(key)
    if count == 1:
        REDIS.expire(key, 60)
    if count > 120:
        raise HTTPException(429, "rate_limited")


def apply_login_delay(username: str, source_ip: str):
    key = f"lf:{username}:{source_ip}"
    attempts = REDIS.incr(key)
    if attempts == 1:
        REDIS.expire(key, 900)
    delay = min(5, max(0, attempts - 1))
    if delay:
        time.sleep(delay)


def clear_login_delay(username: str, source_ip: str):
    REDIS.delete(f"lf:{username}:{source_ip}")


def write_audit(event_type: str, username: str = "", source_ip: str = "", details: dict | None = None):
    payload = details or {}
    with DB.begin() as conn:
        conn.execute(
            text("INSERT INTO audit_logs(username,event_type,source_ip,details) VALUES(:u,:e,:ip,:d::jsonb)"),
            {"u": username or None, "e": event_type, "ip": source_ip or None, "d": json.dumps(payload)},
        )


def noop_ai(message: str) -> str:
    return f"echo: {message[:160]}"


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
    raw = REDIS.get(key)
    if not raw:
        raise HTTPException(401, "invalid_refresh_token")
    claims = json.loads(raw)
    REDIS.delete(key)
    REDIS.srem(f"rt_user:{claims['sub']}", body.refresh_token)
    write_audit("token_refresh", username=claims["sub"])
    return {
        "token": issue_access_token(claims["sub"], claims["role"]),
        "refresh_token": issue_refresh_token(claims["sub"], claims["role"]),
    }


@app.post("/logout")
def logout(body: RefreshIn):
    key = f"rt:{body.refresh_token}"
    raw = REDIS.get(key)
    if not raw:
        return {"ok": True}
    claims = json.loads(raw)
    REDIS.delete(key)
    REDIS.srem(f"rt_user:{claims['sub']}", body.refresh_token)
    write_audit("logout", username=claims["sub"])
    return {"ok": True}


@app.post("/logout_all")
def logout_all(claims=Depends(authz)):
    tokens_key = f"rt_user:{claims['sub']}"
    tokens = REDIS.smembers(tokens_key)
    if tokens:
        pipeline = REDIS.pipeline()
        for token in tokens:
            pipeline.delete(f"rt:{token}")
        pipeline.delete(tokens_key)
        pipeline.execute()
    write_audit("logout_all", username=claims["sub"])
    return {"ok": True, "revoked": len(tokens)}


@app.post("/chat")
def chat(req: ChatIn, claims=Depends(authz), x_api_key: str = Header(default="")):
    check_rate_limit(claims["sub"])
    reply = cb.call(noop_ai, req.message)
    producer.send(
        "events.messages",
        key=claims["sub"].encode(),
        value={"tenant": claims["sub"], "tenant_id": str(uuid.uuid5(uuid.NAMESPACE_DNS, claims["sub"])), "msg": req.message},
    )
    write_audit("chat_used", username=claims["sub"], details={"message_len": len(req.message)})
    return {"reply": reply, "x_api_key_seen": bool(x_api_key)}


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
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    enable_auto_commit=False,
    value_deserializer=lambda m: json.loads(m.decode()),
    security_protocol=os.getenv("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT"),
    sasl_mechanism=os.getenv("KAFKA_SASL_MECHANISM", "PLAIN"),
    sasl_plain_username=os.getenv("KAFKA_USERNAME"),
    sasl_plain_password=os.getenv("KAFKA_PASSWORD"),
)

for msg in consumer:
    try:
        with DB.begin() as conn:
            tenant_id = str(msg.value.get("tenant_id", "")).strip()
            if not tenant_id:
                raise ValueError("missing tenant_id")
            conn.execute(text("INSERT INTO messages(tenant_id,content) VALUES(:t,:c)"),
                         {"t": tenant_id, "c": msg.value.get("msg", "")})
        consumer.commit()
    except Exception:
        producer.send("events.dlq", msg.value)
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

cat > "$APP_DIR/infra/nginx.conf" <<'NGINX'
events {}
http {
  limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
  limit_conn_zone $binary_remote_addr zone=perip:10m;
  gzip on;
  gzip_types text/plain text/css application/json application/javascript application/xml+rss;
  client_max_body_size 1m;

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
    limit_conn perip 30;

    location /api/ {
      limit_req zone=api_limit burst=20 nodelay;
      proxy_pass http://api:8000/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
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
    depends_on: [db, redis, kafka]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    volumes:
      - ../logs:/app/logs
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    networks: [internal]

  worker:
    build: ../worker
    env_file: ../worker/worker.env
    restart: always
    depends_on: [db, kafka]
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    networks: [internal]

  db:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_DB: zeaz
      POSTGRES_USER: zeaz
      POSTGRES_PASSWORD: ${DB_PASS}
    volumes:
      - db_data:/var/lib/postgresql/data
      - ../db/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks: [internal]

  redis:
    image: redis:7
    restart: always
    command: ["redis-server","--requirepass","${REDIS_PASS}","--appendonly","yes","--bind","0.0.0.0","--protected-mode","yes"]
    volumes:
      - redis_data:/data
    networks: [internal]

  zookeeper:
    image: bitnami/zookeeper:latest
    restart: always
    environment:
      ALLOW_ANONYMOUS_LOGIN: "no"
      ZOO_ENABLE_AUTH: "yes"
      ZOO_SERVER_USERS: ${KAFKA_USER}
      ZOO_SERVER_PASSWORDS: ${KAFKA_PASS}
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
      KAFKA_CLIENT_USERS: ${KAFKA_USER}
      KAFKA_CLIENT_PASSWORDS: ${KAFKA_PASS}
      KAFKA_CFG_LOG_RETENTION_HOURS: 168
    networks: [internal]

  nginx:
    build:
      context: ..
      dockerfile: infra/nginx.Dockerfile
    restart: always
    ports:
      - "80:80"
      - "443:443"
    depends_on: [api]
    read_only: true
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
    security_opt:
      - no-new-privileges:true
    cap_drop: ["ALL"]
    networks: [internal, public]

volumes:
  db_data:
  redis_data:
  kafka_data:

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
docker compose up -d --build

log "[5/8] Setup firewall and cron"
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force allow 80/tcp
ufw --force allow 443/tcp
ufw --force enable

(crontab -l 2>/dev/null; echo "0 3 * * * ${APP_DIR}/backup/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * ${APP_DIR}/monitor/health.sh") | crontab -

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
API-specific secrets: ${APP_DIR}/api/api.env
Worker-specific secrets: ${APP_DIR}/worker/worker.env
MSG
