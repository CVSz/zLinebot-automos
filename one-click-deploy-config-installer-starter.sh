#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODE="project"
DOMAIN=""
CERT_EMAIL=""
APP_DIR=""
INSTALL_DEPS="false"
FORCE_CLEAN="false"
AUTO_START="true"
EXPORT_ZIP="false"
ARCHIVE_PATH=""
RUN_HEALTHCHECK="true"

usage() {
  cat <<USAGE
One-click deploy + config + installer + starter for zLineBot-automos.

Usage:
  bash one-click-deploy-config-installer-starter.sh --domain <domain> [options]

Required:
  --domain <domain>            Base domain for generated runtime config.

Options:
  --mode <project|system>      Install mode (default: project).
  --cert-email <email>         Let's Encrypt/contact email for public domains.
  --app-dir <path>             Target deployment directory.
  --install-deps               Install system dependencies (system mode/root only).
  --force-clean                Delete existing target app directory before prepare.
  --no-start                   Prepare config/install but do not launch stack.
  --no-healthcheck             Skip post-start health check.
  --export-zip                 Export prepared stack to tar.gz archive.
  --archive-path <path>        Archive output path (with --export-zip).
  -h, --help                   Show help.

Examples:
  # local workspace dry run / starter
  bash one-click-deploy-config-installer-starter.sh \
    --domain example.local --mode project --app-dir ./zlinebot-automos-stack

  # production host install and start
  sudo bash one-click-deploy-config-installer-starter.sh \
    --mode system --domain example.com --cert-email ops@example.com --install-deps
USAGE
}

log() { printf '[one-click] %s\n' "$*"; }
err() { printf '[one-click][error] %s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing required command: $1"
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --cert-email)
      CERT_EMAIL="${2:-}"
      shift 2
      ;;
    --app-dir)
      APP_DIR="${2:-}"
      shift 2
      ;;
    --install-deps)
      INSTALL_DEPS="true"
      shift
      ;;
    --force-clean)
      FORCE_CLEAN="true"
      shift
      ;;
    --no-start)
      AUTO_START="false"
      shift
      ;;
    --no-healthcheck)
      RUN_HEALTHCHECK="false"
      shift
      ;;
    --export-zip)
      EXPORT_ZIP="true"
      shift
      ;;
    --archive-path)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  err "--domain is required"
  usage
  exit 1
fi

case "$MODE" in
  project)
    APP_DIR="${APP_DIR:-${PWD}/zlinebot-automos-stack}"
    ;;
  system)
    APP_DIR="${APP_DIR:-/opt/zLineBot-automos}"
    ;;
  *)
    err "--mode must be 'project' or 'system'"
    exit 1
    ;;
esac

if [[ "$MODE" == "project" && "$INSTALL_DEPS" == "true" ]]; then
  err "--install-deps is only valid for --mode system"
  exit 1
fi

if [[ "$MODE" == "system" && "$EUID" -ne 0 ]]; then
  err "system mode requires root (run with sudo)."
  exit 1
fi

require_cmd bash
require_cmd docker
if ! docker compose version >/dev/null 2>&1; then
  err "docker compose plugin is required"
  exit 1
fi

INSTALL_ARGS=(
  --mode "$MODE"
  --domain "$DOMAIN"
  --app-dir "$APP_DIR"
  --source-dir "$ROOT_DIR"
)

if [[ "$INSTALL_DEPS" == "false" ]]; then
  INSTALL_ARGS+=(--skip-deps)
fi
if [[ -n "$CERT_EMAIL" ]]; then
  INSTALL_ARGS+=(--cert-email "$CERT_EMAIL")
fi
if [[ "$FORCE_CLEAN" == "true" ]]; then
  INSTALL_ARGS+=(--force-clean)
fi
if [[ "$EXPORT_ZIP" == "true" ]]; then
  INSTALL_ARGS+=(--export-zip)
  if [[ -n "$ARCHIVE_PATH" ]]; then
    INSTALL_ARGS+=(--archive-path "$ARCHIVE_PATH")
  fi
fi

log "Step 1/4: preparing stack + runtime configuration"
bash "$ROOT_DIR/installer/install.sh" "${INSTALL_ARGS[@]}"

if [[ "$AUTO_START" != "true" ]]; then
  log "Step 2/4 skipped: stack start disabled (--no-start)."
  log "Prepared stack path: $APP_DIR"
  log "To start later: bash $APP_DIR/scripts/run-stack.sh up"
  exit 0
fi

log "Step 2/4: starting services with docker compose"
bash "$APP_DIR/scripts/run-stack.sh" up

log "Step 3/4: showing service status"
bash "$APP_DIR/scripts/run-stack.sh" ps

if [[ "$RUN_HEALTHCHECK" == "true" ]]; then
  log "Step 4/4: running health probe (api container)"
  if docker compose -f "$APP_DIR/docker-compose.yml" exec -T api curl -fsS http://localhost:8000/api/health >/dev/null; then
    log "Health check passed: api /api/health"
  else
    err "Health check failed. Check logs with: bash $APP_DIR/scripts/run-stack.sh logs api"
    exit 1
  fi
else
  log "Step 4/4 skipped: health check disabled (--no-healthcheck)."
fi

log "Done. Stack is live from: $APP_DIR"
log "Useful commands:"
log "  bash $APP_DIR/scripts/run-stack.sh logs api"
log "  bash $APP_DIR/scripts/run-stack.sh restart"
log "  bash $APP_DIR/scripts/run-stack.sh down"
