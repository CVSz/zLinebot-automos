#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_NAME="$(basename "$0")"
LOG_DIR_DEFAULT="${ROOT_DIR}/logs"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
LOG_FILE=""

PRIORITY_ORDER=(
  "ubuntu_stack_installer.sh"
  "install_full_stack.sh"
  "zeaz_ai_full_stack_installer.sh"
  "start-zLineBot-automos.sh"
  "one-click-deploy-config-installer-starter.sh"
)

RUN_MODE="plan"
AUTO_CONFIRM="false"
INCLUDE_ALL_SCRIPTS="true"
PASSTHROUGH_ARGS=()

usage() {
  cat <<USAGE
Usage:
  bash ${SELF_NAME} [--plan|--run] [--yes] [--log-file <path>] [--priority-only] [--] [args passed to scripts]

Modes:
  --plan      Inspect duplicate/overlap and print execution priority (default).
  --run       Execute scripts in priority order.

Flags:
  --yes             Skip confirmation prompt in --run mode.
  --log-file PATH   Write all output to PATH (also printed to terminal).
  --priority-only   Skip repository-wide duplicate audit and inspect only priority scripts.
  --help            Show this help.

Notes:
- Duplicate detection includes: exact file hash duplicates + heuristic signature overlap.
- Any extra args after '--' are forwarded to each script while running.
USAGE
}

setup_logging() {
  local target_log="$1"

  if [[ -z "$target_log" ]]; then
    mkdir -p "$LOG_DIR_DEFAULT"
    target_log="${LOG_DIR_DEFAULT}/stack-workflow-${TIMESTAMP}.log"
  else
    mkdir -p "$(dirname "$target_log")"
  fi

  LOG_FILE="$target_log"

  # tee stdout/stderr to log file while preserving console output
  exec > >(tee -a "$LOG_FILE") 2>&1
}

log() { printf '[stack-manager] %s\n' "$*"; }
warn() { printf '[stack-manager][warn] %s\n' "$*"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)
        RUN_MODE="plan"
        shift
        ;;
      --run)
        RUN_MODE="run"
        shift
        ;;
      --yes)
        AUTO_CONFIRM="true"
        shift
        ;;
      --log-file)
        [[ $# -lt 2 ]] && { printf 'Missing value for --log-file\n' >&2; exit 1; }
        LOG_FILE="$2"
        shift 2
        ;;
      --priority-only)
        INCLUDE_ALL_SCRIPTS="false"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        PASSTHROUGH_ARGS+=("$@")
        break
        ;;
      *)
        warn "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

collect_signatures() {
  local script_path="$1"
  sed -E 's/#.*$//' "$script_path" \
    | tr -s '[:space:]' ' ' \
    | sed -E 's/^ +| +$//g' \
    | rg -o '(apt(-get)? install|apt(-get)? update|docker compose|docker-ce|k3s|helm|git clone|installer/install\.sh|run-stack\.sh|systemctl|cloudflared|kubectl|python3? -m venv|pip(3)? install|npm (install|ci|run build)|pnpm (install|build)|yarn (install|build))' \
    | sort -u || true
}

script_inventory() {
  if [[ "$INCLUDE_ALL_SCRIPTS" == "true" ]]; then
    (
      cd "$ROOT_DIR"
      rg --files -g '*.sh' | sort
    )
  else
    printf '%s\n' "${PRIORITY_ORDER[@]}"
  fi
}

inspect_exact_duplicates() {
  log "Scanning for exact duplicate script files..."

  local has_duplicate="false"
  local grouped
  grouped="$({
    while IFS= read -r rel; do
      [[ -f "$ROOT_DIR/$rel" ]] || continue
      printf '%s  %s\n' "$(sha256sum "$ROOT_DIR/$rel" | awk '{print $1}')" "$rel"
    done < <(script_inventory)
  } | sort | awk '{print $1" "$2}')"

  local current_hash=""
  local group=()

  while IFS=' ' read -r hash file; do
    [[ -z "$hash" || -z "$file" ]] && continue

    if [[ "$hash" != "$current_hash" && ${#group[@]} -gt 1 ]]; then
      has_duplicate="true"
      printf '  - duplicate hash %s\n' "$current_hash"
      printf '      • %s\n' "${group[@]}"
    fi

    if [[ "$hash" != "$current_hash" ]]; then
      current_hash="$hash"
      group=("$file")
    else
      group+=("$file")
    fi
  done <<< "$grouped"

  if [[ ${#group[@]} -gt 1 ]]; then
    has_duplicate="true"
    printf '  - duplicate hash %s\n' "$current_hash"
    printf '      • %s\n' "${group[@]}"
  fi

  if [[ "$has_duplicate" == "false" ]]; then
    log "No exact duplicate script content detected."
  fi
}

inspect_overlap() {
  log "Inspecting duplicate/overlapping installer responsibilities..."

  while IFS= read -r script; do
    local path="${ROOT_DIR}/${script}"
    if [[ -f "$path" ]]; then
      local sig
      sig="$(collect_signatures "$path")"
      if [[ -n "$sig" ]]; then
        printf -- '- %s\n' "$script"
        while IFS= read -r line; do
          [[ -n "$line" ]] && printf '    • %s\n' "$line"
        done <<< "$sig"
      else
        printf -- '- %s\n    • (no known signature found)\n' "$script"
      fi
    else
      printf -- '- %s\n    • (missing)\n' "$script"
    fi
  done < <(script_inventory)
}

print_priority() {
  log "Priority order (base setup → full stack → AI stack → bot starter → one-click deploy):"
  local index=1
  for script in "${PRIORITY_ORDER[@]}"; do
    printf '  %d. %s\n' "$index" "$script"
    ((index++))
  done
}

confirm_run() {
  [[ "$AUTO_CONFIRM" == "true" ]] && return 0

  printf 'Proceed with execution in this order? [y/N]: '
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

execute_workflow() {
  print_priority
  if ! confirm_run; then
    warn "Execution cancelled by user."
    exit 1
  fi

  for script in "${PRIORITY_ORDER[@]}"; do
    local path="${ROOT_DIR}/${script}"
    if [[ -f "$path" ]]; then
      log "Running ${script} ..."
      bash "$path" "${PASSTHROUGH_ARGS[@]}"
      log "Finished ${script}."
    else
      warn "${script} not found, skipping."
    fi
  done

  local codex_txt="${ROOT_DIR}/Codex.txt"
  if [[ -f "$codex_txt" ]]; then
    log "Deleting Codex.txt ..."
    rm -f "$codex_txt"
  fi

  log "✅ Stack workflow completed."
}

main() {
  parse_args "$@"
  setup_logging "$LOG_FILE"

  log "Started at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  log "Run mode: ${RUN_MODE}"
  log "Priority-only audit: ${INCLUDE_ALL_SCRIPTS}"
  log "Log file: ${LOG_FILE}"

  inspect_exact_duplicates
  inspect_overlap
  print_priority

  if [[ "$RUN_MODE" == "run" ]]; then
    execute_workflow
  else
    log "Plan mode finished. Run with --run to execute scripts."
  fi
}

main "$@"
