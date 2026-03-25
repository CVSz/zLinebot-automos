#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
PKG_NAME="zBAutomos-enterprise-$(date +%Y%m%d-%H%M%S).tar.gz"

mkdir -p "$OUT_DIR"
tar -czf "${OUT_DIR}/${PKG_NAME}" -C "$ROOT_DIR" \
  api worker hft ai data infra cloudflared backtest options quant analytics install_zba.sh

echo "Release created: ${OUT_DIR}/${PKG_NAME}"
