#!/usr/bin/env bash
set -euo pipefail

curl -fsS http://localhost/ >/dev/null || echo "ALERT: nginx down (http)"
curl -kfsS https://localhost/ >/dev/null || echo "ALERT: nginx down (https)"
