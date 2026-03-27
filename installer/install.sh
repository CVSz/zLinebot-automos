#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"
source "${SCRIPT_DIR}/lib/stack.sh"

MODE="system"
DOMAIN=""
CERT_EMAIL=""
APP_DIR=""
SOURCE_DIR="${REPO_ROOT}"
INSTALL_DEPS="true"
EXPORT_ZIP="false"
ARCHIVE_PATH=""
FORCE_CLEAN="false"


require_option_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    die "Missing value for ${flag}"
  fi
}

usage() {
  cat <<USAGE
Usage:
  sudo bash installer/install.sh --domain <domain> [options]

Options:
  --mode <system|project>   Install into /opt or a caller-provided project path.
  --domain <domain>         Domain used for generated env/TLS assets.
  --cert-email <email>      Email used for Let's Encrypt on public domains.
  --app-dir <path>          Output directory for the prepared stack.
  --source-dir <path>       Source repository to copy from (default: current repo).
  --skip-deps               Skip apt/docker dependency installation.
  --export-zip              Export a tar.gz archive after preparing the stack.
  --archive-path <path>     Output path for exported tar.gz archive.
  --force-clean             Remove the existing app directory before copying files.
  -h, --help                Show this help message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      require_option_value "$1" "${2:-}"
      MODE="$2"
      shift 2
      ;;
    --domain)
      require_option_value "$1" "${2:-}"
      DOMAIN="$2"
      shift 2
      ;;
    --cert-email)
      require_option_value "$1" "${2:-}"
      CERT_EMAIL="$2"
      shift 2
      ;;
    --app-dir)
      require_option_value "$1" "${2:-}"
      APP_DIR="$2"
      shift 2
      ;;
    --source-dir)
      require_option_value "$1" "${2:-}"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --skip-deps)
      INSTALL_DEPS="false"
      shift
      ;;
    --export-zip)
      EXPORT_ZIP="true"
      shift
      ;;
    --archive-path)
      require_option_value "$1" "${2:-}"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --force-clean)
      FORCE_CLEAN="true"
      shift
      ;;
    --skip-full-pack)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

DOMAIN="$(sanitize_domain "$DOMAIN")"
[[ -d "$SOURCE_DIR" ]] || die "Source directory does not exist: ${SOURCE_DIR}"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

case "$MODE" in
  system)
    APP_DIR="${APP_DIR:-/opt/zLineBot-automos}"
    ;;
  project)
    APP_DIR="${APP_DIR:-${PWD}/zlinebot-automos-stack}"
    ;;
  *)
    die "Unsupported mode: ${MODE}"
    ;;
esac

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="${APP_DIR%/}.tar.gz"
fi

if [[ "$MODE" == "system" ]]; then
  require_root
fi

require_cmds free df tar openssl
preflight_checks

if [[ "$INSTALL_DEPS" == "true" ]]; then
  if [[ "$MODE" != "system" ]]; then
    die "--skip-deps is required when using --mode project (apt installs require root)."
  fi
  install_system_packages
else
  require_cmds git
  if [[ -n "$CERT_EMAIL" ]] && is_public_domain "$DOMAIN"; then
    require_cmds docker certbot
  fi
fi

if [[ "$FORCE_CLEAN" == "true" && "$SOURCE_DIR" != "$(cd "$APP_DIR" 2>/dev/null && pwd || printf '__missing__')" ]]; then
  log "Removing existing app directory ${APP_DIR}"
  rm -rf "$APP_DIR"
fi

prepare_stack "$SOURCE_DIR" "$APP_DIR" "$DOMAIN" "$CERT_EMAIL" "$EXPORT_ZIP" "$ARCHIVE_PATH"
log "Prepared ${APP_NAME} stack in ${APP_DIR}"
