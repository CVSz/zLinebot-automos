#!/usr/bin/env bash
set -euo pipefail

docker build -f docker/api.Dockerfile -t zeaz/api:latest .
docker build -f docker/worker.Dockerfile -t zeaz/worker:latest .
