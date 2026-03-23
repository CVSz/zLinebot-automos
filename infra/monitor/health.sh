#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-localhost}"
HTTPS_URL="https://${BASE_URL}"

check() {
  local label="$1"
  local url="$2"
  if curl -kfsS "$url" >/dev/null; then
    echo "[OK] ${label}: ${url}"
  else
    echo "[FAIL] ${label}: ${url}"
    return 1
  fi
}

check "nginx-https-root" "${HTTPS_URL}/"
check "nginx-healthz" "${HTTPS_URL}/healthz"
check "api-health" "${HTTPS_URL}/api/health"

echo "All checks passed."
