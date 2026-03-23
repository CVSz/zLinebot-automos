#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="$ROOT_DIR/.bin"
K8S_DIR="$ROOT_DIR/k8s"
OPA_POLICY="$ROOT_DIR/infrastructure/policies/opa/k8s-security.rego"
KYVERNO_POLICY="$ROOT_DIR/infrastructure/policies/kyverno/require-baseline.yaml"

mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

if ! command -v conftest >/dev/null 2>&1; then
  echo "Installing conftest..."
  curl -sSL https://raw.githubusercontent.com/open-policy-agent/conftest/master/install.sh | bash -s -- -b "$BIN_DIR"
fi

if ! command -v kyverno >/dev/null 2>&1; then
  echo "Installing kyverno CLI..."
  curl -sSL https://github.com/kyverno/kyverno/releases/latest/download/kyverno-cli_v1.14.5_linux_x86_64.tar.gz \
    | tar -xz -C "$BIN_DIR" kyverno
  chmod +x "$BIN_DIR/kyverno"
fi

echo "Running OPA policy checks..."
conftest test "$K8S_DIR"/*.yaml -p "$OPA_POLICY"

echo "Running Kyverno policy checks..."
kyverno apply "$KYVERNO_POLICY" --resource "$K8S_DIR"/*.yaml --audit-warn-exit-code 1

echo "IaC policy checks passed."
