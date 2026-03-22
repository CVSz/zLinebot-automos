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
apt install -y docker.io docker-compose-plugin curl jq openssl ca-certificates
systemctl enable docker
systemctl start docker

log "[3/8] Generate project files"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"/{api,worker,infra,panels/{admin,user,devops},backup,monitor,logs,db}

DB_PASS="$(openssl rand -hex 32)"
REDIS_PASS="$(openssl rand -hex 32)"
JWT_SECRET="$(openssl rand -hex 48)"

cat > "$APP_DIR/.env" <<ENVFILE
DOMAIN=${DOMAIN}
DATABASE_URL=postgresql://zeaz:${DB_PASS}@db:5432/zeaz
JWT_SECRET=${JWT_SECRET}
REDIS_URL=redis://:${REDIS_PASS}@redis:6379/0
KAFKA_BROKER=kafka:9092
OPENAI_API_KEY=REPLACE
ENVFILE

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
  tenant_id INT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
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
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
DOCKER

cat > "$APP_DIR/api/main.py" <<'PYCODE'
import os
import time
import json
from threading import Lock

from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, text
from jose import jwt, JWTError
from passlib.hash import bcrypt
from kafka import KafkaProducer
from redis import Redis

SECRET = os.getenv("JWT_SECRET", "")
DB = create_engine(os.getenv("DATABASE_URL"), pool_pre_ping=True)
REDIS = Redis.from_url(os.getenv("REDIS_URL"), decode_responses=True)
producer = KafkaProducer(
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    value_serializer=lambda v: json.dumps(v).encode()
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

class UserIn(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=8, max_length=128)

class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


def issue_token(username: str, role: str) -> str:
    return jwt.encode({"sub": username, "role": role, "exp": int(time.time()) + 3600}, SECRET, algorithm="HS256")


def authz(authorization: str = Header(default="")):
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing_token")
    token = authorization.split(" ", 1)[1]
    try:
        return jwt.decode(token, SECRET, algorithms=["HS256"])
    except JWTError:
        raise HTTPException(401, "invalid_token")


def check_rate_limit(subject: str):
    key = f"rl:{subject}:{int(time.time() / 60)}"
    count = REDIS.incr(key)
    if count == 1:
        REDIS.expire(key, 60)
    if count > 120:
        raise HTTPException(429, "rate_limited")


def noop_ai(message: str) -> str:
    return f"echo: {message[:160]}"


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/register")
def register(user: UserIn):
    with DB.begin() as conn:
        exists = conn.execute(text("SELECT 1 FROM users WHERE username=:u"), {"u": user.username}).fetchone()
        if exists:
            raise HTTPException(409, "username_exists")
        conn.execute(
            text("INSERT INTO users(username,password,role) VALUES(:u,:p,'user')"),
            {"u": user.username, "p": bcrypt.hash(user.password)}
        )
    return {"ok": True}


@app.post("/login")
def login(user: UserIn):
    with DB.begin() as conn:
        row = conn.execute(text("SELECT password, role FROM users WHERE username=:u"), {"u": user.username}).fetchone()
    if not row or not bcrypt.verify(user.password, row[0]):
        raise HTTPException(401, "invalid_credentials")
    return {"token": issue_token(user.username, row[1])}


@app.post("/chat")
def chat(req: ChatIn, claims=Depends(authz), x_api_key: str = Header(default="")):
    check_rate_limit(claims["sub"])
    reply = cb.call(noop_ai, req.message)
    producer.send("events.messages", key=claims["sub"].encode(), value={"tenant": claims["sub"], "msg": req.message})
    return {"reply": reply, "x_api_key_seen": bool(x_api_key)}


@app.get("/metrics")
def metrics(claims=Depends(authz)):
    if claims.get("role") != "admin":
        raise HTTPException(403, "admin_only")
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
    value_serializer=lambda v: json.dumps(v).encode()
)
consumer = KafkaConsumer(
    "events.messages",
    bootstrap_servers=os.getenv("KAFKA_BROKER"),
    enable_auto_commit=False,
    value_deserializer=lambda m: json.loads(m.decode())
)

for msg in consumer:
    try:
        with DB.begin() as conn:
            conn.execute(text("INSERT INTO messages(tenant_id,content) VALUES(:t,:c)"),
                         {"t": 1, "c": msg.value.get("msg", "")})
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
  server {
    listen 80;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;

    location /api/ {
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
COPY panels/admin /usr/share/nginx/html/admin
COPY panels/user /usr/share/nginx/html/user
COPY panels/devops /usr/share/nginx/html/devops
DOCKER

cat > "$APP_DIR/infra/docker-compose.yml" <<COMPOSE
services:
  api:
    build: ../api
    env_file: ../.env
    restart: always
    depends_on: [db, redis, kafka]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    volumes:
      - ../logs:/app/logs

  worker:
    build: ../worker
    env_file: ../.env
    restart: always
    depends_on: [db, kafka]

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

  redis:
    image: redis:7
    restart: always
    command: ["redis-server","--requirepass","${REDIS_PASS}","--appendonly","yes"]
    volumes:
      - redis_data:/data

  zookeeper:
    image: bitnami/zookeeper:latest
    restart: always
    environment:
      ALLOW_ANONYMOUS_LOGIN: "yes"

  kafka:
    image: bitnami/kafka:latest
    restart: always
    depends_on: [zookeeper]
    volumes:
      - kafka_data:/bitnami/kafka
    environment:
      KAFKA_CFG_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_CFG_LISTENERS: PLAINTEXT://:9092
      KAFKA_CFG_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CFG_LOG_RETENTION_HOURS: 168
      ALLOW_PLAINTEXT_LISTENER: "yes"

  nginx:
    build:
      context: ..
      dockerfile: infra/nginx.Dockerfile
    restart: always
    ports:
      - "80:80"
    depends_on: [api]

volumes:
  db_data:
  redis_data:
  kafka_data:
COMPOSE

cat > "$APP_DIR/backup/backup.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%F_%H-%M)
FILE="/opt/zeaz-v2/backup/db_${TS}.sql.gz"
docker exec $(docker ps -qf name=db) pg_dump -U zeaz zeaz | gzip > "$FILE"
test -s "$FILE"
find /opt/zeaz-v2/backup -type f -mtime +7 -delete
BASH
chmod +x "$APP_DIR/backup/backup.sh"

cat > "$APP_DIR/monitor/health.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
curl -fs http://localhost/ >/dev/null || echo "ALERT: nginx down"
BASH
chmod +x "$APP_DIR/monitor/health.sh"

log "[4/8] Start stack"
cd "$APP_DIR/infra"
docker compose up -d --build

log "[5/8] Setup cron"
(crontab -l 2>/dev/null; echo "0 3 * * * ${APP_DIR}/backup/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * ${APP_DIR}/monitor/health.sh") | crontab -

log "[6/8] Completed"
cat <<MSG
Installed at: ${APP_DIR}
URL: http://${DOMAIN}
Panels:
  - http://${DOMAIN}/admin/
  - http://${DOMAIN}/user/
  - http://${DOMAIN}/devops/
API:
  - POST /api/register
  - POST /api/login
  - POST /api/chat (Bearer token)
NOTE: Update OPENAI_API_KEY in ${APP_DIR}/.env if needed.
MSG
