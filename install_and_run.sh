#!/usr/bin/env bash
# Master Installer + Runner (2026)
# Interactive setup for Automated Bug Finder Loop

set -Eeuo pipefail

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found in PATH."
    exit 1
  fi
}

log "=== Interactive Installer for Repo ==="

require_cmd git
require_cmd awk

read -r -p "Enter the absolute path to your project: " PROJECT_PATH
if [[ -z "${PROJECT_PATH}" ]]; then
  err "Project path is required."
  exit 1
fi

if [[ "${PROJECT_PATH}" == "~"* ]]; then
  PROJECT_PATH="${HOME}${PROJECT_PATH:1}"
fi
if [[ "${PROJECT_PATH}" != /* ]]; then
  PROJECT_PATH="$(pwd)/${PROJECT_PATH}"
fi

if [[ ! -d "${PROJECT_PATH}" ]]; then
  err "Project path does not exist: ${PROJECT_PATH}"
  exit 1
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

read -r -p "Enter Python executable (default: python3): " PYTHON_EXEC
PYTHON_EXEC="${PYTHON_EXEC:-python3}"
if ! command -v "${PYTHON_EXEC}" >/dev/null 2>&1; then
  err "Python executable not found: ${PYTHON_EXEC}"
  exit 1
fi

log "[SETUP] Creating virtual environment..."
"${PYTHON_EXEC}" -m venv "${PROJECT_PATH}/venv"
# shellcheck source=/dev/null
source "${PROJECT_PATH}/venv/bin/activate"

log "[SETUP] Installing dependencies..."
pip install --upgrade pip

installed_from_requirements=0
for req_file in \
  "${PROJECT_PATH}/requirements.txt" \
  "${PROJECT_PATH}/backend/api/requirements.txt" \
  "${PROJECT_PATH}/backend/worker/requirements.txt"
do
  if [[ -f "${req_file}" ]]; then
    log "[SETUP] Installing from ${req_file}..."
    pip install -r "${req_file}"
    installed_from_requirements=1
  fi
done

if [[ "${installed_from_requirements}" -eq 0 ]]; then
  log "[SETUP] No requirements.txt found in expected paths; installing fallback tooling."
  pip install requests pytest
fi

read -r -s -p "Enter your OpenAI/Codex API Key (input hidden): " CODEX_KEY
echo
if [[ -z "${CODEX_KEY}" ]]; then
  warn "No API key entered. bug_finder.py will require CODEX_API_KEY at runtime."
else
  export CODEX_API_KEY="${CODEX_KEY}"
  if ! grep -q '^export CODEX_API_KEY=' "${PROJECT_PATH}/venv/bin/activate"; then
    printf '\nexport CODEX_API_KEY=%q\n' "${CODEX_KEY}" >> "${PROJECT_PATH}/venv/bin/activate"
  else
    warn "CODEX_API_KEY export already exists in venv activate script; leaving as-is."
  fi
fi

cd "${PROJECT_PATH}"
if [[ ! -d ".git" ]]; then
  log "[SETUP] Initializing Git repository..."
  git init
fi

read -r -p "Enter remote Git URL (leave blank to skip): " REMOTE_URL
if [[ -n "${REMOTE_URL}" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    warn "Remote 'origin' already exists."
  else
    git remote add origin "${REMOTE_URL}"
    log "Remote origin added."
  fi
fi

read -r -p "Do you want to run initial tests with pytest? (y/n): " RUN_TESTS
if [[ "${RUN_TESTS,,}" == "y" ]]; then
  if ! pytest; then
    warn "Tests failed, please check manually."
  fi
fi

log "[SETUP] Generating bug_finder.py..."
cat > "${PROJECT_PATH}/bug_finder.py" <<'PYEOF'
#!/usr/bin/env python3
"""
Automated Bug Finder & Updater Loop (2026)
Interactive test/fix loop with LLM-powered patch suggestions.

Security + reliability notes:
- Reads config from environment variables.
- Uses git branch for safety and optional rollback.
- Requires explicit opt-in to push/force-push.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import requests


@dataclass
class Config:
    project_path: Path
    check_interval: int = int(os.getenv("BUG_FINDER_CHECK_INTERVAL", "300"))
    max_iterations: int = int(os.getenv("BUG_FINDER_MAX_ITERATIONS", "50"))
    api_url: str = os.getenv("OPENAI_API_URL", "https://api.openai.com/v1/responses")
    api_key: str | None = os.getenv("CODEX_API_KEY")
    model: str = os.getenv("BUG_FINDER_MODEL", "gpt-5-mini")
    git_push_enabled: bool = os.getenv("BUG_FINDER_GIT_PUSH", "false").lower() == "true"
    git_force_push_on_rollback: bool = (
        os.getenv("BUG_FINDER_FORCE_PUSH_ROLLBACK", "false").lower() == "true"
    )


def _run(cmd: list[str], cwd: Path, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, check=check)


def run_tests(cfg: Config) -> tuple[int, str, str]:
    try:
        result = _run(["pytest", "--maxfail=5", "--disable-warnings", "-q"], cwd=cfg.project_path)
        return result.returncode, result.stdout, result.stderr
    except Exception as exc:  # pylint: disable=broad-except
        return 1, "", str(exc)


def analyze_output(stdout: str, stderr: str) -> list[str]:
    issues: list[str] = []
    for line in list(stdout.splitlines()) + list(stderr.splitlines()):
        if "FAILED" in line or "ERROR" in line:
            issues.append(line.strip())
    return issues


def _extract_text_from_responses(payload: dict) -> str:
    output = payload.get("output", [])
    chunks: list[str] = []
    for item in output:
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                chunks.append(content.get("text", ""))
    if chunks:
        return "\n".join(chunks)
    return payload.get("output_text", "") or ""


def codex_patch(cfg: Config, issue: str) -> str | None:
    if not cfg.api_key:
        print("[ERROR] CODEX_API_KEY is not set.")
        return None

    headers = {
        "Authorization": f"Bearer {cfg.api_key}",
        "Content-Type": "application/json",
    }
    prompt = f"""
You are a senior Python engineer. A pytest failure occurred in this project:
Project path: {cfg.project_path}
Failure:
{issue}

Return only patch instructions in this exact format:
FILE: <relative_path>
OLD: <exact old code>
NEW: <exact replacement code>

Rules:
- Keep changes minimal.
- Do not include markdown fences.
- Ensure replacement compiles.
""".strip()

    body = {
        "model": cfg.model,
        "input": prompt,
    }

    try:
        resp = requests.post(cfg.api_url, headers=headers, json=body, timeout=60)
        if resp.status_code != 200:
            print(f"[ERROR] API request failed ({resp.status_code}): {resp.text}")
            return None
        data = resp.json()
        patch_text = _extract_text_from_responses(data).strip()
        print(f"[CODEX PATCH] Suggested fix:\n{patch_text}")
        return patch_text or None
    except Exception as exc:  # pylint: disable=broad-except
        print(f"[ERROR] API call exception: {exc}")
        return None


def apply_patch(cfg: Config, patch_text: str) -> bool:
    file_pattern = re.compile(r"^FILE:\s*(.+)$")
    old_pattern = re.compile(r"^OLD:\s*(.+)$")
    new_pattern = re.compile(r"^NEW:\s*(.+)$")

    current_file: Path | None = None
    old_code: str | None = None
    updated_any = False

    for line in patch_text.splitlines():
        file_match = file_pattern.match(line)
        old_match = old_pattern.match(line)
        new_match = new_pattern.match(line)

        if file_match:
            current_file = (cfg.project_path / file_match.group(1).strip()).resolve()
            if cfg.project_path.resolve() not in current_file.parents and current_file != cfg.project_path.resolve():
                print(f"[ERROR] Refusing to patch outside project: {current_file}")
                current_file = None
        elif old_match:
            old_code = old_match.group(1)
        elif new_match:
            new_code = new_match.group(1)
            if current_file and old_code is not None:
                try:
                    content = current_file.read_text(encoding="utf-8")
                    if old_code in content:
                        current_file.write_text(content.replace(old_code, new_code), encoding="utf-8")
                        print(f"[PATCH APPLIED] {current_file}")
                        updated_any = True
                    else:
                        print(f"[WARNING] OLD code not found in {current_file}")
                except Exception as exc:  # pylint: disable=broad-except
                    print(f"[ERROR] Failed to apply patch: {exc}")
            old_code = None

    return updated_any


def attempt_fix(cfg: Config, issues: Iterable[str]) -> bool:
    changed = False
    log_path = cfg.project_path / "codex_patch.log"
    for issue in issues:
        print(f"[AI PATCH] Attempting fix for: {issue}")
        patch = codex_patch(cfg, issue)
        if patch and apply_patch(cfg, patch):
            changed = True
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(f"\nIssue: {issue}\nPatch:\n{patch}\n")
    return changed


def current_head(cfg: Config) -> str | None:
    result = _run(["git", "rev-parse", "HEAD"], cwd=cfg.project_path)
    return result.stdout.strip() if result.returncode == 0 else None


def create_fix_branch(cfg: Config, iteration: int) -> str | None:
    branch = f"auto/bug-finder-{int(time.time())}-{iteration}"
    result = _run(["git", "checkout", "-b", branch], cwd=cfg.project_path)
    if result.returncode == 0:
        return branch
    print(f"[ERROR] Cannot create branch: {result.stderr}")
    return None


def commit_changes(cfg: Config) -> bool:
    _run(["git", "add", "-A"], cwd=cfg.project_path)
    status = _run(["git", "status", "--porcelain"], cwd=cfg.project_path)
    if not status.stdout.strip():
        print("[INFO] No file changes to commit.")
        return False

    commit = _run(["git", "commit", "-m", "Automated bug fix via Codex loop"], cwd=cfg.project_path)
    if commit.returncode != 0:
        print(f"[ERROR] Commit failed: {commit.stderr}")
        return False

    if cfg.git_push_enabled:
        push = _run(["git", "push", "-u", "origin", "HEAD"], cwd=cfg.project_path)
        if push.returncode != 0:
            print(f"[ERROR] Push failed: {push.stderr}")
            return False

    return True


def rollback_changes(cfg: Config, baseline_sha: str) -> None:
    reset = _run(["git", "reset", "--hard", baseline_sha], cwd=cfg.project_path)
    if reset.returncode != 0:
        print(f"[ERROR] Rollback reset failed: {reset.stderr}")
        return

    if cfg.git_push_enabled and cfg.git_force_push_on_rollback:
        force_push = _run(["git", "push", "--force-with-lease", "origin", "HEAD"], cwd=cfg.project_path)
        if force_push.returncode != 0:
            print(f"[ERROR] Force push rollback failed: {force_push.stderr}")
            return

    print("[ROLLBACK] Reverted to baseline due to regression.")


def main_loop() -> None:
    project_path = Path(os.getenv("BUG_FINDER_PROJECT_PATH", Path.cwd())).resolve()
    cfg = Config(project_path=project_path)

    if not cfg.project_path.exists():
        raise SystemExit(f"Project path does not exist: {cfg.project_path}")

    for iteration in range(1, cfg.max_iterations + 1):
        print(f"\n[LOOP] Iteration {iteration}/{cfg.max_iterations}")
        baseline_sha = current_head(cfg)
        if not baseline_sha:
            print("[ERROR] Could not read current git HEAD. Exiting.")
            return

        _, stdout, stderr = run_tests(cfg)
        issues = analyze_output(stdout, stderr)

        if not issues:
            print("[CLEAN] No bugs detected.")
            time.sleep(cfg.check_interval)
            continue

        print(f"[BUGS FOUND] {len(issues)} issues detected.")
        if not create_fix_branch(cfg, iteration):
            return

        changed = attempt_fix(cfg, issues)
        if not changed:
            print("[INFO] No applicable patch produced.")
            time.sleep(cfg.check_interval)
            continue

        if not commit_changes(cfg):
            print("[ERROR] Commit/push step failed.")
            time.sleep(cfg.check_interval)
            continue

        _, stdout_after, stderr_after = run_tests(cfg)
        issues_after = analyze_output(stdout_after, stderr_after)

        if len(issues_after) > len(issues):
            print("[ROLLBACK TRIGGERED] Patch introduced more failures.")
            rollback_changes(cfg, baseline_sha)
        else:
            print("[PATCH SUCCESS] Tests improved or stable.")

        time.sleep(cfg.check_interval)


if __name__ == "__main__":
    main_loop()
PYEOF
chmod +x "${PROJECT_PATH}/bug_finder.py"

log "=== Installation Complete ==="
log "To start bug finder loop, activate venv and run:"
echo "source ${PROJECT_PATH}/venv/bin/activate"
echo "BUG_FINDER_PROJECT_PATH=${PROJECT_PATH} python bug_finder.py"
