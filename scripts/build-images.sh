#!/usr/bin/env bash
set -euo pipefail

docker build -f docker/api.Dockerfile -t zlinebot-automos/api:latest .
docker build -f docker/worker.Dockerfile -t zlinebot-automos/worker:latest .
