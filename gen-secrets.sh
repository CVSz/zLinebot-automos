#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-zlinebot-automos.local}"
CERT_EMAIL="${2:-admin@${DOMAIN}}"
APP_HOST="app.${DOMAIN}"
API_HOST="api.${DOMAIN}"

DB_PASS="$(openssl rand -hex 32)"
REDIS_PASS="$(openssl rand -hex 32)"
JWT_SECRET_CURRENT="$(openssl rand -hex 48)"
KAFKA_USER="zlinebot_app"
KAFKA_PASS="$(openssl rand -hex 24)"
ADMIN_PASS="$(openssl rand -base64 18)"

cat > .env <<ENV
DOMAIN=${DOMAIN}
DB_PASS=${DB_PASS}
REDIS_PASS=${REDIS_PASS}
JWT_SECRET_CURRENT=${JWT_SECRET_CURRENT}
JWT_SECRET_PREVIOUS=
KAFKA_USER=${KAFKA_USER}
KAFKA_PASS=${KAFKA_PASS}
ADMIN_PASS=${ADMIN_PASS}
OPENAI_API_KEY=REPLACE
CERT_EMAIL=${CERT_EMAIL}
CLOUDFLARED_TUNNEL_ID=replace-with-your-tunnel-uuid
APP_HOST=${APP_HOST}
API_HOST=${API_HOST}
WILDCARD_HOST=
DATABASE_URL=postgresql://zlinebot:${DB_PASS}@db:5432/zlinebot_automos
REDIS_URL=redis://:${REDIS_PASS}@redis:6379/0
KAFKA_BROKER=kafka:9092
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=PLAIN
KAFKA_USERNAME=${KAFKA_USER}
KAFKA_PASSWORD=${KAFKA_PASS}
CORS_ALLOW_ORIGINS=https://${APP_HOST},https://${API_HOST}
ENV

echo "Generated $(pwd)/.env for ${DOMAIN}"
