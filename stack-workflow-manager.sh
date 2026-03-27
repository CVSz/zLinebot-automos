#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_NAME="$(basename "$0")"

PRIORITY_ORDER=(
  "ubuntu_stack_installer.sh"
  "install_full_stack.sh"
  "zeaz_ai_full_stack_installer.sh"
  "start-zLineBot-automos.sh"
  "one-click-deploy-config-installer-starter.sh"
)

RUN_MODE="plan"
AUTO_CONFIRM="false"
PASSTHROUGH_ARGS=()

usage() {
  cat <<USAGE
Usage:
  bash ${SELF_NAME} [--plan|--run] [--yes] [--] [args passed to scripts]

Modes:
  --plan      Inspect duplicate/overlap and print execution priority (default).
  --run       Execute scripts in priority order.

Flags:
  --yes       Skip confirmation prompt in --run mode.
  --help      Show this help.

Notes:
- Overlap detection is heuristic: compares command signatures and key runtime actions.
- Any extra args after '--' are forwarded to each script while running.
USAGE
}

log() { printf '[stack-manager] %s\n' "$*"; }
warn() { printf '[stack-manager][warn] %s\n' "$*" >&2; }

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
    | rg -o '(apt(-get)? install|apt(-get)? update|docker compose|docker-ce|k3s|helm|git clone|installer/install\.sh|run-stack\.sh|systemctl|cloudflared|kubectl)' \
    | sort -u
}

inspect_overlap() {
  log "Inspecting duplicate/overlapping installer responsibilities..."

  for script in "${PRIORITY_ORDER[@]}"; do
    local path="${ROOT_DIR}/${script}"
    if [[ -f "$path" ]]; then
      local sig
      sig="$(collect_signatures "$path" || true)"
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
  done
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
  inspect_overlap
  print_priority

  if [[ "$RUN_MODE" == "run" ]]; then
    execute_workflow
  else
    log "Plan mode finished. Run with --run to execute scripts."
  fi
}

main "$@"
