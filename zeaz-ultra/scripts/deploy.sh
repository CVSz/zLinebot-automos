#!/usr/bin/env bash
set -euo pipefail

echo "🚀 BUILD"
bash scripts/build.sh

echo "📤 PUSH"
docker push zeaz/api:latest
docker push zeaz/worker:latest

echo "☸️ DEPLOY K8s"
kubectl apply -f k8s/

echo "⚡ DONE"
