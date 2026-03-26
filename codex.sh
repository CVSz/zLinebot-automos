#!/usr/bin/env bash
# =========================================================
# 🚀 FULL CODEX INSTALLER - zLineBot-Automos ENTERPRISE
# =========================================================

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/CVSz/zLinebot-automos.git"
TARGET_DIR_DEFAULT="zLinebot-automos"
CODEX_CONFIG_DIR="${HOME}/.codex"
CODEX_CONFIG_FILE="${CODEX_CONFIG_DIR}/config.toml"

DB_NAME_DEFAULT="zlinebot"
DB_USER_DEFAULT="zbot_user"
DB_PASS_DEFAULT=""

log() {
  printf '[codex] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

random_secret() {
  require_cmd openssl
  openssl rand -hex 32
}

ensure_repo() {
  local target_dir="$1"
  local repo_url="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    log "Using existing repository at ${target_dir}"
    return
  fi

  if [[ -d .git ]]; then
    log "Already inside a git repository, skipping clone"
    return
  fi

  require_cmd git
  log "Cloning repository from ${repo_url}"
  git clone "${repo_url}" "${target_dir}"
}

resolve_paths() {
  local project_dir="$1"

  ROOT_DIR="$project_dir"
  AUTONOMOS_DIR="$project_dir/autonomos"

  if [[ ! -d "$AUTONOMOS_DIR" ]]; then
    log "Could not find autonomos runtime directory at ${AUTONOMOS_DIR}"
    exit 1
  fi

  SCHEMA_FILE="$AUTONOMOS_DIR/db/schema.sql"
  AUTONOMOS_ENV_FILE="$AUTONOMOS_DIR/.env"
}

install_dependencies() {
  log "Installing workspace dependencies"
  require_cmd npm

  (cd "$ROOT_DIR" && npm install)
  (cd "$AUTONOMOS_DIR" && npm install)
}

setup_postgres_redis() {
  log "Installing and enabling PostgreSQL + Redis"
  require_cmd sudo

  sudo apt-get update
  sudo apt-get install -y postgresql postgresql-contrib redis-server
  sudo systemctl enable postgresql redis-server
  sudo systemctl start postgresql redis-server

  local db_password="$1"

  sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
    CREATE DATABASE ${DB_NAME};
  END IF;
END \$\$;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${db_password}';
  ELSE
    ALTER ROLE ${DB_USER} WITH PASSWORD '${db_password}';
  END IF;
END \$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL
}

apply_schema() {
  local db_password="$1"

  if [[ ! -f "$SCHEMA_FILE" ]]; then
    log "Schema file not found at ${SCHEMA_FILE}; skipping schema migration"
    return
  fi

  log "Applying SQL schema from ${SCHEMA_FILE}"
  PGPASSWORD="$db_password" psql \
    --host=localhost \
    --username="$DB_USER" \
    --dbname="$DB_NAME" \
    --file="$SCHEMA_FILE"
}

create_env_file() {
  local db_password="$1"

  if [[ -f "$AUTONOMOS_ENV_FILE" ]]; then
    log "autonomos/.env already exists, skipping"
    return
  fi

  local jwt_secret
  jwt_secret="$(random_secret)"

  cat > "$AUTONOMOS_ENV_FILE" <<ENVEOF
NODE_ENV=production
PORT=3300
WS_PORT=4000
JWT_SECRET=${jwt_secret}
DATABASE_URL=postgres://${DB_USER}:${db_password}@localhost:5432/${DB_NAME}
REDIS_URL=redis://localhost:6379
OPENAI_API_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_ID=
APP_BASE_URL=http://localhost:3300
ENVEOF

  log "Created ${AUTONOMOS_ENV_FILE} with generated JWT secret"
}

create_run_script() {
  cat > "${ROOT_DIR}/run.sh" <<'RUNEOF'
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting zLineBot-Automos runtime..."
cd autonomos
npm start
RUNEOF

  chmod +x "${ROOT_DIR}/run.sh"
  log "Created run.sh"
}

install_codex_cli() {
  require_cmd npm
  log "Installing @openai/codex CLI globally"
  npm install -g @openai/codex
}

write_codex_config() {
  mkdir -p "$CODEX_CONFIG_DIR"

  cat > "$CODEX_CONFIG_FILE" <<CONFEOF
model = "gpt-5-codex"
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[profiles.fast]
model = "o4-mini"
model_reasoning_effort = "low"

[profiles.safe]
approval_policy = "on-request"
sandbox_mode = "read-only"
CONFEOF

  log "Wrote Codex config to ${CODEX_CONFIG_FILE}"
}

verify_openai_api_key() {
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    log "No OPENAI_API_KEY detected. Export it before running Codex automation."
  fi
}

run_codex_auto_setup() {
  if ! command -v codex >/dev/null 2>&1; then
    log "codex command not found; skipping auto setup"
    return
  fi

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    log "Skipping Codex auto setup: OPENAI_API_KEY is not set."
    return
  fi

  log "Running Codex auto setup"
  (
    cd "$ROOT_DIR"
    codex "analyze this LINE bot project, verify dependencies, run relevant tests, identify the top 3 production risks, and propose minimal safe fixes."
  )
}

launch_application() {
  log "Launching zLineBot-Automos"
  (cd "$ROOT_DIR" && ./run.sh)
}

package_k8s_bundle() {
  local bundle_name="$1"
  local k8s_dir="${ROOT_DIR}/k8s"

  if [[ ! -d "$k8s_dir" ]]; then
    log "k8s directory not found at ${k8s_dir}; skipping bundle export"
    return
  fi

  if ! command -v zip >/dev/null 2>&1; then
    log "zip command not available; skipping k8s bundle export"
    return
  fi

  log "Packaging Kubernetes + Terraform bundle to ${bundle_name}"
  (
    cd "$ROOT_DIR"
    rm -f "$bundle_name"
    zip -r "$bundle_name" k8s >/dev/null
  )
}

usage() {
  cat <<'USAGE'
Usage: bash codex.sh [options]

Options:
  --repo-url <url>      Git repository URL (default: official zLinebot-automos repo)
  --target-dir <dir>    Target directory for clone/use (default: zLinebot-automos)
  --db-name <name>      PostgreSQL database name (default: zlinebot)
  --db-user <user>      PostgreSQL app user (default: zbot_user)
  --db-pass <pass>      PostgreSQL app password (default: generated random)
  --skip-system         Skip apt/systemctl PostgreSQL + Redis setup
  --skip-codex          Skip Codex CLI install + auto setup
  --skip-launch         Skip launching run.sh at the end
  --skip-schema         Skip SQL schema apply step
  --package-k8s         Export k8s/ as a zip bundle after setup
  --k8s-bundle-name     Zip filename for --package-k8s (default: zlinebot-k8s-bundle.zip)
  -h, --help            Show help
USAGE
}

main() {
  local repo_url="$REPO_URL_DEFAULT"
  local target_dir="$TARGET_DIR_DEFAULT"
  local skip_system="false"
  local skip_codex="false"
  local skip_launch="false"
  local skip_schema="false"
  local package_k8s="false"
  local k8s_bundle_name="zlinebot-k8s-bundle.zip"

  DB_NAME="$DB_NAME_DEFAULT"
  DB_USER="$DB_USER_DEFAULT"
  DB_PASS="$DB_PASS_DEFAULT"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-url)
        repo_url="${2:-}"
        shift 2
        ;;
      --target-dir)
        target_dir="${2:-}"
        shift 2
        ;;
      --db-name)
        DB_NAME="${2:-}"
        shift 2
        ;;
      --db-user)
        DB_USER="${2:-}"
        shift 2
        ;;
      --db-pass)
        DB_PASS="${2:-}"
        shift 2
        ;;
      --skip-system)
        skip_system="true"
        shift
        ;;
      --skip-codex)
        skip_codex="true"
        shift
        ;;
      --skip-launch)
        skip_launch="true"
        shift
        ;;
      --skip-schema)
        skip_schema="true"
        shift
        ;;
      --package-k8s)
        package_k8s="true"
        shift
        ;;
      --k8s-bundle-name)
        k8s_bundle_name="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "$DB_PASS" ]]; then
    DB_PASS="$(random_secret)"
    log "Generated random database password"
  fi

  log "Starting zLineBot-Automos enterprise installer"
  ensure_repo "$target_dir" "$repo_url"

  local project_dir
  if [[ -d "${target_dir}/.git" ]]; then
    project_dir="$target_dir"
  else
    project_dir="$(pwd)"
  fi

  resolve_paths "$project_dir"
  install_dependencies

  if [[ "$skip_system" == "false" ]]; then
    setup_postgres_redis "$DB_PASS"
  else
    log "Skipping PostgreSQL + Redis setup"
  fi

  if [[ "$skip_schema" == "false" ]]; then
    apply_schema "$DB_PASS"
  else
    log "Skipping SQL schema apply"
  fi

  create_env_file "$DB_PASS"
  create_run_script

  if [[ "$skip_codex" == "false" ]]; then
    install_codex_cli
    write_codex_config
    verify_openai_api_key
    run_codex_auto_setup
  else
    log "Skipping Codex install/config/auto setup"
  fi

  if [[ "$skip_launch" == "false" ]]; then
    launch_application
  else
    log "Skipping application launch"
  fi

  if [[ "$package_k8s" == "true" ]]; then
    package_k8s_bundle "$k8s_bundle_name"
  fi

  log "DONE - zLineBot-Automos enterprise SaaS installer completed"
}

main "$@"
