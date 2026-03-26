# Infrastructure CI Policy & Self-Healing Scripts

## Contents

- `scripts/check-iac-policy.sh`: runs OPA (`conftest`) and Kyverno validation against `k8s/*.yaml`.
- `scripts/auto-fix-pipeline.sh`: applies safe automated remediations (script permissions and YAML whitespace normalization).
- `policies/opa/k8s-security.rego`: baseline Kubernetes security policy checks.
- `policies/kyverno/require-baseline.yaml`: baseline Kyverno policy used in CI.

## Local usage

```bash
./infrastructure/scripts/check-iac-policy.sh
./infrastructure/scripts/auto-fix-pipeline.sh
```

## CI/CD audit

- Self-healing pipeline problem inventory and remediation status:
  - `docs/self-healing-cicd-problems.md`

## Documentation Refresh — 2026-03-26 (UTC)

- Reconfirmed IaC policy and self-healing script references for local and CI usage.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

