#!/usr/bin/env bash
set -euo pipefail

: "${DB_PASS:?DB_PASS is required}"
: "${ADMIN_PASS:?ADMIN_PASS is required}"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${1:-/tmp/zlinebot-automos-backups}"
mkdir -p "${OUT_DIR}"

PLAIN_DUMP="${OUT_DIR}/zlinebot_automos_${STAMP}.dump"
ENC_FILE="${PLAIN_DUMP}.enc"

export PGPASSWORD="${DB_PASS}"
pg_dump -h db -U zlinebot -d zlinebot_automos -Fc -f "${PLAIN_DUMP}"

openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
  -in "${PLAIN_DUMP}" \
  -out "${ENC_FILE}" \
  -pass env:ADMIN_PASS

SHA_FILE="${ENC_FILE}.sha256"
sha256sum "${ENC_FILE}" > "${SHA_FILE}"
rm -f "${PLAIN_DUMP}"

echo "Encrypted backup: ${ENC_FILE}"
echo "Checksum file: ${SHA_FILE}"
