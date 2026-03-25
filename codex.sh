#!/usr/bin/env bash
# =========================================================
# 🚀 FULL CODEX INSTALLER - zLineBot-Automos ENTERPRISE
# =========================================================

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/CVSz/zLinebot-automos.git"
TARGET_DIR_DEFAULT="zLinebot-automos"
ENV_FILE_NAME=".env"
CODEX_CONFIG_DIR="${HOME}/.codex"
CODEX_CONFIG_FILE="${CODEX_CONFIG_DIR}/config.toml"

log() {
  printf '[codex] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
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

detect_project_type() {
  local project_dir="$1"

  if [[ -f "${project_dir}/package.json" ]]; then
    echo "node"
  elif [[ -f "${project_dir}/requirements.txt" ]]; then
    echo "python"
  elif [[ -f "${project_dir}/go.mod" ]]; then
    echo "go"
  else
    echo "unknown"
  fi
}

install_dependencies() {
  local project_dir="$1"
  local project_type="$2"

  log "Installing dependencies for ${project_type}"
  case "$project_type" in
    node)
      require_cmd npm
      (cd "$project_dir" && npm install)
      ;;
    python)
      require_cmd pip
      (cd "$project_dir" && pip install -r requirements.txt)
      ;;
    go)
      require_cmd go
      (cd "$project_dir" && go mod tidy)
      ;;
    *)
      log "Unknown project type; skipping dependency install"
      ;;
  esac
}

setup_postgres_redis() {
  log "Installing and enabling PostgreSQL + Redis"
  require_cmd sudo

  sudo apt-get update
  sudo apt-get install -y postgresql postgresql-contrib redis-server
  sudo systemctl enable postgresql redis-server
  sudo systemctl start postgresql redis-server

  sudo -u postgres psql <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'zlinebot') THEN
    CREATE DATABASE zlinebot;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'zbot_user') THEN
    CREATE ROLE zbot_user LOGIN PASSWORD 'zbot_pass';
  END IF;
END $$;

GRANT ALL PRIVILEGES ON DATABASE zlinebot TO zbot_user;
SQL
}

create_env_file() {
  local project_dir="$1"
  local env_file="${project_dir}/${ENV_FILE_NAME}"

  if [[ -f "$env_file" ]]; then
    log "${ENV_FILE_NAME} already exists, skipping"
    return
  fi

  cat > "$env_file" <<'ENVEOF'
PORT=3000
NODE_ENV=production
JWT_SECRET=YOUR_SECRET_KEY
LINE_CHANNEL_ACCESS_TOKEN=PUT_YOUR_TOKEN_HERE
LINE_CHANNEL_SECRET=PUT_YOUR_SECRET_HERE
POSTGRES_URL=postgres://zbot_user:zbot_pass@localhost:5432/zlinebot
REDIS_URL=redis://localhost:6379
STRIPE_KEY=PUT_YOUR_STRIPE_KEY_HERE
CLOUDFLARE_TUNNEL=PUT_YOUR_TUNNEL_TOKEN
ENVEOF

  log "Created ${env_file}; update with production credentials"
}

create_run_script() {
  local project_dir="$1"

  cat > "${project_dir}/run.sh" <<'RUNEOF'
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting zLineBot-Automos..."
if [[ -f package.json ]]; then
  npm start || node index.js || node app.js
elif [[ -f app.py ]]; then
  python app.py
elif [[ -f main.go ]]; then
  go run main.go
else
  echo "❌ No entry point found"
  exit 1
fi
RUNEOF

  chmod +x "${project_dir}/run.sh"
  log "Created run.sh"
}

install_codex_cli() {
  require_cmd npm
  log "Installing @openai/codex CLI globally"
  npm install -g @openai/codex
}

write_codex_config() {
  local project_root="$1"
  mkdir -p "$CODEX_CONFIG_DIR"

  cat > "$CODEX_CONFIG_FILE" <<CONFEOF
model = "gpt-5-codex"
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
context_compression = true
cache_enabled = true
parallel_tasks = true
max_threads = 8
auto_fix_errors = true
auto_install_dependencies = true
verbosity = "medium"

[model_provider]
name = "openai"
base_url = "https://api.openai.com/v1"
env_key = "OPENAI_API_KEY"

[environment]
shell = "/bin/bash"
network_access = true
workspace_dir = "${project_root}"
process_timeout = 600

[repo]
root = "${project_root}"
default_branch = "main"
auto_commit = true
auto_push = false
commit_message = "🤖 Codex automated update"
branch_prefix = "bot/"
ignore_paths = [".git", "node_modules", "logs", "temp", "*.log", "memory.json"]

[tools.git]
enabled = true
auto_fetch = true

[tools.shell]
enabled = true

[tools.filesystem]
enabled = true

[features]
multi_agent = true
auto_planning = true
self_healing = true
task_queue = true
chat_memory = true
affiliate_system = true
push_notifications = true
compliance = true
analytics = true
saas_scaling = true
CONFEOF

  log "Wrote Codex config to ${CODEX_CONFIG_FILE}"
}

verify_openai_api_key() {
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    log "No OPENAI_API_KEY detected. Export it before running Codex automation."
  fi
}

run_codex_auto_setup() {
  local project_dir="$1"

  if ! command -v codex >/dev/null 2>&1; then
    log "codex command not found; skipping auto setup"
    return
  fi

  log "Running Codex auto setup"
  (
    cd "$project_dir"
    codex -- --auto-edit "analyze this LINE bot project, install dependencies, setup PostgreSQL + Redis, configure JWT auth, setup Stripe + marketplace, setup WebSocket dashboard, setup Kubernetes deployment templates, setup affiliate referral + push notifications + compliance + analytics + multi-user SaaS, optimize for production enterprise"
  )
}

launch_application() {
  local project_dir="$1"
  log "Launching zLineBot-Automos"
  (cd "$project_dir" && ./run.sh)
}

usage() {
  cat <<'USAGE'
Usage: bash codex.sh [options]

Options:
  --repo-url <url>      Git repository URL (default: official zLinebot-automos repo)
  --target-dir <dir>    Target directory for clone/use (default: zLinebot-automos)
  --skip-system         Skip apt/systemctl PostgreSQL + Redis setup
  --skip-codex          Skip Codex CLI install + auto setup
  --skip-launch         Skip launching run.sh at the end
  -h, --help            Show help
USAGE
}

main() {
  local repo_url="$REPO_URL_DEFAULT"
  local target_dir="$TARGET_DIR_DEFAULT"
  local skip_system="false"
  local skip_codex="false"
  local skip_launch="false"

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

  log "Starting zLineBot-Automos enterprise installer"
  ensure_repo "$target_dir" "$repo_url"

  local project_dir
  if [[ -d "${target_dir}/.git" ]]; then
    project_dir="$target_dir"
  else
    project_dir="$(pwd)"
  fi

  local project_type
  project_type="$(detect_project_type "$project_dir")"
  log "Detected project type: ${project_type}"

  install_dependencies "$project_dir" "$project_type"

  if [[ "$skip_system" == "false" ]]; then
    setup_postgres_redis
  else
    log "Skipping PostgreSQL + Redis setup"
  fi

  create_env_file "$project_dir"
  create_run_script "$project_dir"

  if [[ "$skip_codex" == "false" ]]; then
    install_codex_cli
    write_codex_config "$project_dir"
    verify_openai_api_key
    run_codex_auto_setup "$project_dir"
  else
    log "Skipping Codex install/config/auto setup"
  fi

  if [[ "$skip_launch" == "false" ]]; then
    launch_application "$project_dir"
  else
    log "Skipping application launch"
  fi

  log "DONE - zLineBot-Automos enterprise SaaS installer completed"
}

main "$@"
