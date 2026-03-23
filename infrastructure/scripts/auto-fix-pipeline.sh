#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[self-heal] Normalizing script executable bits"
find infrastructure/scripts -maxdepth 1 -type f -name '*.sh' -print0 | while IFS= read -r -d '' script; do
  chmod +x "$script"
done

echo "[self-heal] Normalizing YAML style where possible"
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path

for yaml_path in Path('.').glob('**/*.yml'):
    text = yaml_path.read_text(encoding='utf-8')
    normalized = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    if text != normalized:
        yaml_path.write_text(normalized, encoding='utf-8')
for yaml_path in Path('.').glob('**/*.yaml'):
    text = yaml_path.read_text(encoding='utf-8')
    normalized = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    if text != normalized:
        yaml_path.write_text(normalized, encoding='utf-8')
PY
fi

echo "[self-heal] Candidate fixes generated."
git status --short
