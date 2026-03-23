#!/usr/bin/env bash
set -euo pipefail

: "${DB_PASS:?DB_PASS is required}"
: "${ADMIN_PASS:?ADMIN_PASS is required}"

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${1:-/tmp/zeaz-backups}"
mkdir -p "${OUT_DIR}"

PLAIN_SQL="${OUT_DIR}/zeaz_${STAMP}.sql"
ENC_FILE="${PLAIN_SQL}.enc"

PGPASSWORD="${DB_PASS}" pg_dump -h db -U zeaz -d zeaz > "${PLAIN_SQL}"
openssl enc -aes-256-cbc -salt -pbkdf2 -in "${PLAIN_SQL}" -out "${ENC_FILE}" -pass env:ADMIN_PASS
rm -f "${PLAIN_SQL}"

echo "Encrypted backup written to ${ENC_FILE}"
