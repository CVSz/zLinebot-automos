#!/bin/bash
set -euo pipefail

echo "🚀 Installing zBAutomos"

apt update
apt install -y docker.io docker-compose nginx

systemctl enable docker

(cd infra && docker-compose up -d)

echo "☸️ Deploying Kubernetes"
kubectl apply -f infra/k8s/

echo "🌐 Starting Cloudflare tunnel"
cloudflared tunnel run zba

echo "✅ DONE"
