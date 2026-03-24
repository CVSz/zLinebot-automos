#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/installer/lib/common.sh"
source "${SCRIPT_DIR}/installer/lib/runtime.sh"

INSTALL_DIR="/opt/${APP_NAME}"
VERSION_FILE="${INSTALL_DIR}/.version.lock"
REPO_URL="${REPO_URL:-https://github.com/CVSz/zLineBot-automos.git}"
BRANCH="${BRANCH:-main}"
SERVICE_NAME="${APP_NAME}.service"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
SELF_NAME="$(basename "$0")"

usage() {
  cat <<USAGE
Usage:
  ${SELF_NAME} install --domain <domain> [--cert-email <email>] [--version <ref>] [--repo <git_url>]
  ${SELF_NAME} start
  ${SELF_NAME} stop
  ${SELF_NAME} restart
  ${SELF_NAME} status
  ${SELF_NAME} logs
  ${SELF_NAME} update
  ${SELF_NAME} upgrade
  ${SELF_NAME} uninstall
  ${SELF_NAME} lock-version <tag_or_commit>

Environment overrides:
  REPO_URL   Git URL used for install/update/upgrade (default: ${REPO_URL})
  BRANCH     Default branch used when no version lock is present (default: ${BRANCH})
USAGE
}

ensure_runtime() {
  require_cmds git systemctl docker
  if ! docker compose version >/dev/null 2>&1; then
    install_system_packages
  fi
}

ensure_install_exists() {
  [[ -d "${INSTALL_DIR}" ]] || die "${APP_NAME} is not installed in ${INSTALL_DIR}. Run '${SELF_NAME} install' first."
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
Description=${APP_NAME} full stack
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose -f ${COMPOSE_FILE} up -d --build
ExecStop=/usr/bin/docker compose -f ${COMPOSE_FILE} down
ExecReload=/usr/bin/docker compose -f ${COMPOSE_FILE} up -d --build
RemainAfterExit=true
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
}

prepare_install_tree() {
  local domain="$1"
  local cert_email="$2"
  bash "${INSTALL_DIR}/installer/install.sh" \
    --mode system \
    --domain "$domain" \
    --cert-email "$cert_email" \
    --app-dir "${INSTALL_DIR}" \
    --source-dir "${INSTALL_DIR}" \
    --skip-deps

  pushd "${INSTALL_DIR}" >/dev/null
  git update-index --skip-worktree .env backend/api/api.env backend/worker/worker.env infra/certs/fullchain.pem infra/certs/privkey.pem || true
  popd >/dev/null
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

status_service() {
  ensure_install_exists
  systemctl status "${SERVICE_NAME}" --no-pager
}

logs_service() {
  ensure_install_exists
  docker compose -f "${COMPOSE_FILE}" logs --tail=100
}

install_app() {
  local version=""
  local domain=""
  local cert_email=""

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
      --domain)
        domain="${2:-}"
        shift 2
        ;;
      --cert-email)
        cert_email="${2:-}"
        shift 2
        ;;
      *)
        die "Unknown install option: $1"
        ;;
    esac
  done

  [[ -n "$domain" ]] || die "install requires --domain <domain>"

  require_root
  preflight_checks
  ensure_runtime
  clone_or_update_repo "$version"
  prepare_install_tree "$domain" "$cert_email"

  if [[ -n "$version" ]]; then
    printf '%s\n' "$version" > "${VERSION_FILE}"
    log "Locked ${APP_NAME} to version: ${version}"
  fi

  create_service
  start_service
  log "${APP_NAME} full stack install complete in ${INSTALL_DIR}."
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
    die "Version is locked to '${locked}'. Use '${SELF_NAME} upgrade' to force update or change lock with '${SELF_NAME} lock-version <ref>'."
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
    status)
      require_root
      status_service
      ;;
    logs)
      require_root
      logs_service
      ;;
    update)
      update_app
      ;;
    upgrade)
      upgrade_app
      ;;
    uninstall)
      uninstall_app
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
