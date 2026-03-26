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

detect_node_entry() {
  local project_dir="$1"
  local entry=""

  if [[ -f "${project_dir}/package.json" ]]; then
    entry="$(
      cd "$project_dir" &&
      node -e "try{const p=require('./package.json');console.log(p.main||'')}catch(e){console.log('')}"
    )"
  fi

  if [[ -z "$entry" ]]; then
    for f in index.js app.js server.js main.js; do
      if [[ -f "${project_dir}/${f}" ]]; then
        entry="$f"
        break
      fi
    done
  fi

  if [[ -z "$entry" ]]; then
    entry="$(
      cd "$project_dir" &&
      find . -type f -name "*.js" \
        ! -path "./node_modules/*" \
        ! -path "./dist/*" \
        ! -path "./build/*" | head -n 1
    )"
  fi

  entry="${entry#./}"
  echo "$entry"
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
  local node_entry="${2:-}"

  cat > "${project_dir}/run.sh" <<RUNEOF
#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting zLineBot-Automos..."
if [[ -f package.json ]]; then
  if npm run | grep -qE '^[[:space:]]*start'; then
    npm start
  elif [[ -n "${node_entry}" && -f "${node_entry}" ]]; then
    node "${node_entry}"
  else
    ENTRY=\$(find . -type f -name "*.js" ! -path "./node_modules/*" | head -n 1 || true)
    if [[ -n "\${ENTRY}" ]]; then
      node "\${ENTRY}"
    else
      echo "❌ No JS entry point found"
      exit 1
    fi
  fi
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
  log "Created run.sh (node entry: ${node_entry:-not detected})"
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

[profiles.fast]
model = "o4-mini"
model_reasoning_effort = "low"

[profiles.safe]
approval_policy = "on-request"
sandbox_mode = "read-only"
CONFEOF

  log "Wrote Codex config to ${CODEX_CONFIG_FILE}"
  log "Config scoped for ${project_root}"
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

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    log "Skipping Codex auto setup: OPENAI_API_KEY is not set."
    return
  fi

  log "Running Codex auto setup"
  (
    cd "$project_dir"
    codex "analyze this LINE bot project, verify dependencies, run relevant tests, identify the top 3 production risks, and propose minimal safe fixes."
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

  local node_entry=""
  if [[ "$project_type" == "node" ]]; then
    node_entry="$(detect_node_entry "$project_dir")"
    log "Detected Node.js entry: ${node_entry:-NOT FOUND}"
  fi

  install_dependencies "$project_dir" "$project_type"

  if [[ "$skip_system" == "false" ]]; then
    setup_postgres_redis
  else
    log "Skipping PostgreSQL + Redis setup"
  fi

  create_env_file "$project_dir"
  create_run_script "$project_dir" "$node_entry"

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
