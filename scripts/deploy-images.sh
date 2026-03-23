#!/usr/bin/env bash
set -euo pipefail

echo "🚀 BUILD"
bash scripts/build.sh

echo "📤 PUSH"
docker push zlinebot-automos/api:latest
docker push zlinebot-automos/worker:latest

echo "☸️ DEPLOY K8s"
kubectl apply -f k8s/

echo "⚡ DONE"
