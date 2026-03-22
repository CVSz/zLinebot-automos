#!/usr/bin/env bash
# FINAL MERGED RELEASE
# Ubuntu 24.04 | LINE AI Funnel + Growth Engine + TLS | Production
# Usage:
#   sudo bash zeaz_ai_full_stack_installer.sh --domain your-domain.com --email you@example.com

set -euo pipefail

DOMAIN=""
EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Usage: --domain your-domain.com --email you@example.com"
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

APP_DIR="/opt/zeaz-ai"
APP_USER="zeaz"
APP_GROUP="$APP_USER"
DB_NAME="zeazai"
DB_USER="zeaz_user"
DB_PASS="StrongPass_Change"
SERVICE_NAME="zeaz-ai"
GROWTH_SERVICE_NAME="zeaz-growth"
SYNC_SERVICE_NAME="zeaz-tiktok-sync"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "[1/15] Install base packages"
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y python3 python3-venv python3-pip nginx redis-server postgresql certbot python3-certbot-nginx git curl ufw

log "[2/15] Create app user + folders"
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$APP_USER"
fi
mkdir -p "$APP_DIR"
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"

log "[3/15] Setup PostgreSQL (idempotent)"
sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '${DB_USER}') THEN
    CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
    CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
  END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL

log "[4/15] Python virtualenv + dependencies"
sudo -u "$APP_USER" bash <<'EOT1'
set -euo pipefail
cd /opt/zeaz-ai
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install \
  fastapi \
  uvicorn[standard] \
  line-bot-sdk \
  openai \
  redis \
  sqlalchemy \
  psycopg2-binary \
  tenacity \
  structlog \
  orjson \
  pandas \
  scikit-learn \
  gspread \
  google-auth \
  watchdog
EOT1

log "[5/15] Create app.py (multi-agent webhook)"
sudo -u "$APP_USER" bash <<'EOT2'
cat > /opt/zeaz-ai/app.py <<'PY'
import os
import time
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from linebot import LineBotApi, WebhookHandler
from linebot.models import MessageEvent, TextMessage, TextSendMessage
from linebot.exceptions import InvalidSignatureError
from openai import OpenAI
import redis
from sqlalchemy import create_engine, text

LINE_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN")
LINE_SECRET = os.getenv("LINE_CHANNEL_SECRET")
OPENAI_KEY = os.getenv("OPENAI_API_KEY")

if not all([LINE_TOKEN, LINE_SECRET, OPENAI_KEY]):
    raise RuntimeError("Missing required LINE/OpenAI environment variables")

line_api = LineBotApi(LINE_TOKEN)
handler = WebhookHandler(LINE_SECRET)
client = OpenAI(api_key=OPENAI_KEY)

redis_client = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"), decode_responses=True)
engine = create_engine(os.getenv("DATABASE_URL"), pool_pre_ping=True)

app = FastAPI(title="ZEAZ LINE AI")


def ensure_schema():
    with engine.begin() as conn:
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS users (
                user_id TEXT PRIMARY KEY,
                total_spent NUMERIC DEFAULT 0,
                segment TEXT DEFAULT 'NORMAL',
                last_active TIMESTAMPTZ DEFAULT NOW()
            )
        """))


def rate(uid: str) -> bool:
    key = f"rl:{uid}"
    now = int(time.time())
    pipe = redis_client.pipeline()
    pipe.zremrangebyscore(key, 0, now - 10)
    pipe.zcard(key)
    pipe.zadd(key, {str(now): now})
    pipe.expire(key, 10)
    _, count, _, _ = pipe.execute()
    return count < 20


def ai(system_prompt: str, message: str) -> str:
    response = client.chat.completions.create(
        model=os.getenv("MODEL_NAME", "gpt-4.1-mini"),
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": message},
        ],
        max_tokens=300,
    )
    return (response.choices[0].message.content or "").strip() or "ขออภัย ระบบไม่สามารถตอบกลับได้ในขณะนี้"


def intent(message: str) -> str:
    lower = message.lower()
    if any(x in lower for x in ["ราคา", "ซื้อ", "โปร", "promotion", "discount"]):
        return "sales"
    if any(x in lower for x in ["ปัญหา", "เสีย", "เคลม", "error", "issue"]):
        return "support"
    return "general"


@app.on_event("startup")
def startup_event():
    ensure_schema()


@app.post("/webhook")
async def webhook(req: Request):
    signature = req.headers.get("X-Line-Signature", "")
    body = await req.body()
    try:
        handler.handle(body.decode("utf-8"), signature)
    except InvalidSignatureError:
        raise HTTPException(status_code=400, detail="Invalid signature")
    return JSONResponse({"ok": True})


@handler.add(MessageEvent, message=TextMessage)
def handle(e):
    uid = e.source.user_id
    msg = e.message.text.strip()

    with engine.begin() as conn:
        conn.execute(text("""
            INSERT INTO users (user_id, last_active)
            VALUES (:u, NOW())
            ON CONFLICT (user_id) DO UPDATE SET last_active = NOW()
        """), {"u": uid})

    if not rate(uid):
        reply = "Too many requests"
    else:
        i = intent(msg)
        if i == "sales":
            reply = ai("You are a high-conversion sales closer.", msg)
        elif i == "support":
            reply = ai("You are a concise support specialist.", msg)
        else:
            reply = ai("You are a helpful assistant. Analyze intent and gently upsell where relevant.", msg)

    line_api.reply_message(e.reply_token, TextSendMessage(text=reply))


@app.get("/health")
def health():
    return {"ok": True}
PY
EOT2

log "[6/15] Create growth.py"
sudo -u "$APP_USER" bash <<'EOT3'
cat > /opt/zeaz-ai/growth.py <<'PY'
import os
import pandas as pd
from sqlalchemy import create_engine, text
from sklearn.cluster import KMeans
from linebot import LineBotApi
from linebot.models import TextSendMessage

DB = create_engine(os.getenv("DATABASE_URL"), pool_pre_ping=True)
line = LineBotApi(os.getenv("LINE_CHANNEL_ACCESS_TOKEN"))


def segment():
    df = pd.read_sql("SELECT user_id, COALESCE(total_spent, 0) AS total_spent FROM users", DB)
    if len(df) < 5:
        return
    kmeans = KMeans(n_clusters=3, n_init=10, random_state=42).fit(df[["total_spent"]])
    df["seg"] = kmeans.labels_.astype(str)
    with DB.begin() as conn:
        for _, r in df.iterrows():
            conn.execute(
                text("UPDATE users SET segment = :s WHERE user_id = :u"),
                {"s": r["seg"], "u": r["user_id"]},
            )


def followup():
    with DB.begin() as conn:
        rows = conn.execute(text("""
            SELECT user_id
            FROM users
            WHERE last_active < NOW() - INTERVAL '3 days'
            LIMIT 100
        """)).fetchall()
    for r in rows:
        line.push_message(r[0], TextSendMessage(text="🔥 โปรพิเศษกลับมาวันนี้"))


def broadcast(seg: str, msg: str):
    with DB.begin() as conn:
        rows = conn.execute(
            text("SELECT user_id FROM users WHERE segment = :s LIMIT 200"),
            {"s": seg},
        ).fetchall()
    for r in rows:
        line.push_message(r[0], TextSendMessage(text=msg))
PY
EOT3

log "[7/15] Create runner.py"
sudo -u "$APP_USER" bash <<'EOT4'
cat > /opt/zeaz-ai/runner.py <<'PY'
import time
from growth import segment, followup, broadcast

while True:
    try:
        segment()
        followup()
        broadcast("VIP", "🔥 VIP SALE 30% วันนี้")
    except Exception as exc:
        print(exc)
    time.sleep(3600)
PY
EOT4

log "[8/15] Create TikTok export sync worker"
sudo -u "$APP_USER" bash <<'EOT5'
mkdir -p /opt/zeaz-ai/exports
cat > /opt/zeaz-ai/tiktok_sync.py <<'PY'
import csv
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import gspread
from google.oauth2.service_account import Credentials
from sqlalchemy import create_engine, text
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

DATABASE_URL = os.getenv("DATABASE_URL")
LINE_CHANNEL_ACCESS_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN")
GOOGLE_SHEET_ID = os.getenv("GOOGLE_SHEET_ID", "")
GOOGLE_SERVICE_ACCOUNT_JSON = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON", "")
EXPORT_DIR = os.getenv("TIKTOK_EXPORT_DIR", "/opt/zeaz-ai/exports")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL missing")

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
REQUIRED_FIELDS = ["Order ID", "Buyer Name", "Phone", "Address"]


def ensure_orders_table():
    with engine.begin() as conn:
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS orders (
                order_id TEXT PRIMARY KEY,
                buyer_name TEXT NOT NULL,
                phone TEXT NOT NULL,
                address TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'tiktok_export',
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """))


def get_sheet():
    if not GOOGLE_SHEET_ID or not GOOGLE_SERVICE_ACCOUNT_JSON:
        return None
    info = json.loads(GOOGLE_SERVICE_ACCOUNT_JSON)
    creds = Credentials.from_service_account_info(
        info,
        scopes=[
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ],
    )
    client = gspread.authorize(creds)
    return client.open_by_key(GOOGLE_SHEET_ID).sheet1


def normalize(row: dict) -> dict:
    return {
        "order_id": str(row["Order ID"]).strip(),
        "buyer_name": str(row["Buyer Name"]).strip(),
        "phone": str(row["Phone"]).strip(),
        "address": str(row["Address"]).strip(),
        "synced_at": datetime.now(timezone.utc).isoformat(),
    }


def upsert_order(payload: dict):
    with engine.begin() as conn:
        conn.execute(text("""
            INSERT INTO orders(order_id, buyer_name, phone, address, synced_at)
            VALUES (:order_id, :buyer_name, :phone, :address, NOW())
            ON CONFLICT (order_id)
            DO UPDATE SET
                buyer_name = EXCLUDED.buyer_name,
                phone = EXCLUDED.phone,
                address = EXCLUDED.address,
                synced_at = NOW()
        """), payload)


def append_sheet(sheet, payload: dict):
    if not sheet:
        return
    sheet.append_row(
        [
            payload["order_id"],
            payload["buyer_name"],
            payload["phone"],
            payload["address"],
            payload["synced_at"],
        ],
        value_input_option="USER_ENTERED",
    )


def process_csv(path: Path):
    sheet = get_sheet()
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED_FIELDS if c not in reader.fieldnames]
        if missing:
            raise ValueError(f"CSV schema invalid, missing columns: {missing}")

        for row in reader:
            payload = normalize(row)
            if not payload["order_id"]:
                continue
            upsert_order(payload)
            append_sheet(sheet, payload)


class ExportHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory or not event.src_path.endswith(".csv"):
            return
        process_csv(Path(event.src_path))


def run():
    ensure_orders_table()
    Path(EXPORT_DIR).mkdir(parents=True, exist_ok=True)

    for item in Path(EXPORT_DIR).glob("*.csv"):
        process_csv(item)

    observer = Observer()
    observer.schedule(ExportHandler(), EXPORT_DIR, recursive=False)
    observer.start()
    try:
        observer.join()
    except KeyboardInterrupt:
        observer.stop()
        observer.join()


if __name__ == "__main__":
    run()
PY
EOT5

log "[9/15] Create .env"
cat > "$APP_DIR/.env" <<EOT5
LINE_CHANNEL_ACCESS_TOKEN=REPLACE
LINE_CHANNEL_SECRET=REPLACE
OPENAI_API_KEY=REPLACE
MODEL_NAME=gpt-4.1-mini
REDIS_URL=redis://127.0.0.1:6379/0
DATABASE_URL=postgresql+psycopg2://${DB_USER}:${DB_PASS}@127.0.0.1:5432/${DB_NAME}
TIKTOK_EXPORT_DIR=/opt/zeaz-ai/exports
GOOGLE_SHEET_ID=REPLACE
GOOGLE_SERVICE_ACCOUNT_JSON=REPLACE
EOT5
chown "$APP_USER:$APP_GROUP" "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"

log "[10/15] systemd services"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOT6
[Unit]
Description=ZEAZ AI LINE Webhook
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000 --workers 4
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOT6

cat > "/etc/systemd/system/${GROWTH_SERVICE_NAME}.service" <<EOT7
[Unit]
Description=ZEAZ AI Growth Engine
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/python runner.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOT7

cat > "/etc/systemd/system/${SYNC_SERVICE_NAME}.service" <<EOT8
[Unit]
Description=ZEAZ TikTok Export Sync
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/python tiktok_sync.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOT8

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" "$GROWTH_SERVICE_NAME" "$SYNC_SERVICE_NAME"

log "[11/15] Nginx site"
cat > /etc/nginx/sites-available/zeaz-ai <<EOT9
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOT9
ln -sf /etc/nginx/sites-available/zeaz-ai /etc/nginx/sites-enabled/zeaz-ai
nginx -t
systemctl restart nginx

log "[12/15] TLS via certbot"
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect

log "[13/15] Firewall"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

log "[14/15] Start services"
systemctl restart "$SERVICE_NAME" "$GROWTH_SERVICE_NAME" "$SYNC_SERVICE_NAME"

log "[15/15] COMPLETE"
echo "Webhook URL: https://${DOMAIN}/webhook"
echo "Remember to set LINE_CHANNEL_ACCESS_TOKEN / LINE_CHANNEL_SECRET / OPENAI_API_KEY in ${APP_DIR}/.env"
echo "For TikTok export sync, set GOOGLE_SHEET_ID and GOOGLE_SERVICE_ACCOUNT_JSON in ${APP_DIR}/.env"
