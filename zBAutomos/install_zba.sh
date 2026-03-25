#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/zba"
DOMAIN="api.zeaz.dev"
REPO_URL="${ZBA_REPO_URL:-https://github.com/YOUR_REPO/zBAutomos.git}"
ENV_FILE="${APP_DIR}/.env"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

echo "[1/8] Install base dependencies..."
apt-get update
apt-get install -y docker.io docker-compose nginx git curl redis-server postgresql openssl

systemctl enable docker
systemctl start docker
systemctl enable redis-server postgresql
systemctl start redis-server postgresql

echo "[2/8] Clone/update project..."
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch --all --tags
  git -C "$APP_DIR" reset --hard origin/$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)
else
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"

echo "[3/8] Setup environment..."
JWT_SECRET="$(openssl rand -hex 32)"
cat > "$ENV_FILE" <<EOT
NODE_ENV=production
DB_URL=postgres://postgres:password@localhost:5432/zba
REDIS_URL=redis://localhost:6379
JWT_SECRET=${JWT_SECRET}
BINANCE_KEY=
BINANCE_SECRET=
EOT

echo "[4/8] Start core services..."
docker-compose -f infra/docker-compose.yml up -d --build

echo "[5/8] Setup DB..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'zba'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE zba;"

echo "[6/8] Nginx config..."
cat > /etc/nginx/sites-available/zba <<EOT
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOT

ln -sf /etc/nginx/sites-available/zba /etc/nginx/sites-enabled/zba
nginx -t
systemctl restart nginx

echo "[7/8] Cloudflare tunnel (optional)..."
if command -v cloudflared >/dev/null 2>&1; then
  cloudflared tunnel run zba || true
else
  echo "cloudflared not installed; skipping tunnel step"
fi

echo "[8/8] DONE 🚀"
