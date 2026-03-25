#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Deploying zLineBot Enterprise"

docker build -t zlinebot .
kubectl apply -f k8s/
kubectl autoscale deployment zlinebot-automos-api --cpu-percent=70 --min=2 --max=10

echo "✅ Deployed"
