# zLineBot-automos Self-Healing CI/CD Problem Audit

This audit lists observed problems in `.github/workflows/self-healing-cicd.yml` and related scripts,
with remediation status as of 2026-03-24.

## Critical / High

1. **Over-broad workflow permissions for all jobs**
   - **Problem:** `contents: write` and `pull-requests: write` were granted globally, even for the validation job.
   - **Risk:** unnecessary token exposure and elevated blast radius if a build step is compromised.
   - **Status:** **Fixed** by setting read-only permissions on `validate-and-build` and write permissions only on `self-healing`.

2. **Self-healing PR creation could run for non-push contexts**
   - **Problem:** self-healing was gated only on failure + output flag.
   - **Risk:** PRs could be attempted from unsupported contexts, creating noisy/failed automation.
   - **Status:** **Fixed** by restricting to `push` on `refs/heads/main`.

3. **Gate logic allowed non-success outcomes to pass silently**
   - **Problem:** gate only marked `failure` as failed; other outcomes (`cancelled`, `skipped`) were not treated as failed.
   - **Risk:** false-green CI gate.
   - **Status:** **Fixed** by treating any non-`success` outcome as failed.

## Medium

4. **Mass YAML normalization scanned entire tree**
   - **Problem:** self-heal script used recursive globs over all files.
   - **Risk:** touching unintended YAML files and producing noisy remediation PRs.
   - **Status:** **Fixed** by limiting normalization to tracked YAML files via `git ls-files`.

5. **Worker test step failed hard when tests directory did not exist**
   - **Problem:** workflow always ran `pytest -q backend/worker/tests`.
   - **Risk:** predictable failures on repositories/branches lacking worker tests.
   - **Status:** **Fixed** by conditionally running the test command only when test files exist.

6. **Unnecessary Docker daemon startup in GitHub-hosted runner**
   - **Problem:** compose validation attempted `systemctl start docker`.
   - **Risk:** brittle execution and avoidable noise in logs.
   - **Status:** **Fixed** by removing daemon startup and relying on runner-provided Docker service.

7. **Manual Trivy installation via curl/tar in CI**
   - **Problem:** direct binary download/install in workflow.
   - **Risk:** avoidable supply-chain and maintenance burden.
   - **Status:** **Fixed** by switching to `aquasecurity/trivy-action`.

## Low / Operational debt (still open)

1. **No artifact upload of failure diagnostics**
   - Missing junit/test logs/artifacts for rapid post-failure triage.

2. **Self-heal script currently does formatting and chmod only**
   - No semantic remediation (dependency/version rollback, deterministic patch sets, targeted failure parsing).

3. **No mandatory human approval gate for self-heal PR merge**
   - Should be enforced via branch protection + CODEOWNERS.

4. **No checksum verification in `check-iac-policy.sh` tool downloads**
   - Could be hardened with pinned checksums/signature validation.

## Recommended next improvements

- Upload artifacts for all validation failures (pytest logs, compose config, policy outputs, trivy report).
- Add deterministic remediation bundles keyed off failing step IDs.
- Add checksum/SLSA verification for downloaded CLI tools.
- Integrate shellcheck/yamllint for faster pre-gate failures.

## Documentation Refresh — 2026-03-26 (UTC)

- Revalidated CI/CD remediation notes against the current `.github/workflows` and `infrastructure/scripts` layout.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

