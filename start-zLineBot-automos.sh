#!/usr/bin/env bash

set -euo pipefail

APP_NAME="zLineBot-automos"
INSTALL_DIR="/opt/${APP_NAME}"
VERSION_FILE="${INSTALL_DIR}/.version.lock"
REPO_URL="${REPO_URL:-https://github.com/example/${APP_NAME}.git}"
BRANCH="${BRANCH:-main}"
SERVICE_NAME="${APP_NAME}.service"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

SCRIPT_NAME="$(basename "$0")"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

usage() {
  cat <<USAGE
Usage:
  ${SCRIPT_NAME} install [--version <tag_or_commit>] [--repo <git_url>]
  ${SCRIPT_NAME} uninstall
  ${SCRIPT_NAME} start
  ${SCRIPT_NAME} stop
  ${SCRIPT_NAME} restart
  ${SCRIPT_NAME} update
  ${SCRIPT_NAME} upgrade
  ${SCRIPT_NAME} lock-version <tag_or_commit>

Environment overrides:
  REPO_URL   Git URL used for install/update/upgrade (default: ${REPO_URL})
  BRANCH     Default git branch (default: ${BRANCH})
USAGE
}

require_cmds() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

ensure_runtime() {
  require_cmds git systemctl

  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    apt-get update
    apt-get install -y docker.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
  fi
}

ensure_install_exists() {
  [[ -d "${INSTALL_DIR}" ]] || die "${APP_NAME} is not installed in ${INSTALL_DIR}. Run '${SCRIPT_NAME} install' first."
}

current_lock_version() {
  if [[ -f "${VERSION_FILE}" ]]; then
    tr -d '[:space:]' < "${VERSION_FILE}"
  fi
}

resolve_target_ref() {
  local locked
  locked="$(current_lock_version || true)"
  if [[ -n "${locked}" ]]; then
    printf '%s' "${locked}"
  else
    printf '%s' "${BRANCH}"
  fi
}

clone_or_update_repo() {
  local explicit_ref="${1:-}"

  if [[ ! -d "${INSTALL_DIR}/.git" ]]; then
    rm -rf "${INSTALL_DIR}"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi

  pushd "${INSTALL_DIR}" >/dev/null
  git remote set-url origin "${REPO_URL}"
  git fetch --all --tags --prune

  local target_ref
  if [[ -n "${explicit_ref}" ]]; then
    target_ref="${explicit_ref}"
  else
    target_ref="$(resolve_target_ref)"
  fi

  if git rev-parse --verify --quiet "origin/${target_ref}" >/dev/null; then
    git checkout -B "${BRANCH}" "origin/${target_ref}"
  else
    git checkout "${target_ref}"
  fi
  popd >/dev/null
}

create_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}" <<UNIT
[Unit]
Description=${APP_NAME} stack
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose -f ${COMPOSE_FILE} up -d
ExecStop=/usr/bin/docker compose -f ${COMPOSE_FILE} down
RemainAfterExit=true
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
}

start_service() {
  ensure_install_exists
  [[ -f "${COMPOSE_FILE}" ]] || die "Missing ${COMPOSE_FILE}"
  systemctl start "${SERVICE_NAME}"
  log "${APP_NAME} started."
}

stop_service() {
  ensure_install_exists
  systemctl stop "${SERVICE_NAME}" || true
  log "${APP_NAME} stopped."
}

restart_service() {
  ensure_install_exists
  systemctl restart "${SERVICE_NAME}"
  log "${APP_NAME} restarted."
}

install_app() {
  local version=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        version="${2:-}"
        shift 2
        ;;
      --repo)
        REPO_URL="${2:-}"
        shift 2
        ;;
      *)
        die "Unknown install option: $1"
        ;;
    esac
  done

  require_root
  ensure_runtime

  clone_or_update_repo "${version}"

  if [[ -n "${version}" ]]; then
    mkdir -p "${INSTALL_DIR}"
    printf '%s\n' "${version}" > "${VERSION_FILE}"
    log "Locked ${APP_NAME} to version: ${version}"
  fi

  create_service
  start_service
  log "${APP_NAME} install complete in ${INSTALL_DIR}."
}

uninstall_app() {
  require_root

  if systemctl list-unit-files | awk '{print $1}' | grep -qx "${SERVICE_NAME}"; then
    systemctl stop "${SERVICE_NAME}" || true
    systemctl disable "${SERVICE_NAME}" || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}"
    systemctl daemon-reload
  fi

  rm -rf "${INSTALL_DIR}"
  log "${APP_NAME} uninstalled."
}

update_app() {
  require_root
  ensure_install_exists

  local locked
  locked="$(current_lock_version || true)"
  if [[ -n "${locked}" ]]; then
    die "Version is locked to '${locked}'. Use '${SCRIPT_NAME} upgrade' to force update or change lock with '${SCRIPT_NAME} lock-version <ref>'."
  fi

  clone_or_update_repo "${BRANCH}"
  restart_service
  log "${APP_NAME} updated to latest ${BRANCH}."
}

upgrade_app() {
  require_root
  ensure_install_exists

  clone_or_update_repo "${BRANCH}"
  rm -f "${VERSION_FILE}"
  restart_service
  log "${APP_NAME} upgraded to latest ${BRANCH} and version lock cleared."
}

lock_version() {
  require_root
  ensure_install_exists

  local version="${1:-}"
  [[ -n "${version}" ]] || die "Please provide a tag or commit."

  clone_or_update_repo "${version}"
  printf '%s\n' "${version}" > "${VERSION_FILE}"
  restart_service
  log "${APP_NAME} locked to ${version}."
}

main() {
  local action="${1:-}"
  shift || true

  case "${action}" in
    install)
      install_app "$@"
      ;;
    uninstall)
      uninstall_app
      ;;
    start)
      require_root
      start_service
      ;;
    stop)
      require_root
      stop_service
      ;;
    restart)
      require_root
      restart_service
      ;;
    update)
      update_app
      ;;
    upgrade)
      upgrade_app
      ;;
    lock-version)
      lock_version "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "Unknown command: ${action}. Use --help for usage."
      ;;
  esac
}

main "$@"
