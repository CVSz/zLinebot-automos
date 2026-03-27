# zLineBot-automos

## 0) One-click deploy-config-installer-starter

Run a single command to prepare config, install stack files, start Docker services, and run a health probe:

```bash
bash one-click-deploy-config-installer-starter.sh --domain example.local --mode project --app-dir ./zlinebot-automos-stack
```

Production host example:

```bash
sudo bash one-click-deploy-config-installer-starter.sh --mode system --domain example.com --cert-email ops@example.com --install-deps
```

A production-oriented CRM + LINE automation stack with:
- **FastAPI API** (`backend/api`)
- **Kafka worker** (`backend/worker`)
- **React frontend** (`frontend`)
- **Postgres + Redis + Kafka + NGINX** orchestration via Docker Compose

## Project Structure

```text
frontend/              React CRM dashboard
backend/api/           FastAPI tenant-aware CRM API
backend/worker/        Kafka-based broadcast delivery worker
backend/db/init.sql    Database bootstrap
infra/                 NGINX, certs, cloudflared, monitoring helpers
installer/             Full installer and stack preparation logic
scripts/               Build/deploy/start operational scripts
k8s/                   Kubernetes manifests
```

## 1) Full Installer (Recommended)

### System install (live host)

```bash
sudo bash zeaz_ai_full_stack_installer.sh --domain example.com --cert-email ops@example.com
```

This prepares runtime dependencies, generates secrets and env files, provisions TLS assets, and readies the stack in `/opt/zLineBot-automos`.

### Project-mode install (non-root / workspace)

```bash
bash ubuntu_stack_installer.sh --domain example.local --skip-deps --app-dir ./zlinebot-automos-stack
```

> In project mode, dependency installation is skipped by design. Install Docker tooling separately.

## 1.1) Stack workflow manager (dedupe + ordered execution)

Use the workflow manager to inspect overlapping stack responsibilities and run scripts in a safe priority order:

```bash
bash stack-workflow-manager.sh --plan
```

Run the ordered workflow:

```bash
bash stack-workflow-manager.sh --run --yes
```

Default priority:
1. `ubuntu_stack_installer.sh`
2. `install_full_stack.sh`
3. `zeaz_ai_full_stack_installer.sh`
4. `start-zLineBot-automos.sh`
5. `one-click-deploy-config-installer-starter.sh`

## 1.5) Enterprise `codex.sh` bootstrap

Generate enterprise env secrets, spin up core services (PostgreSQL/Redis/Kafka/API/Worker), and export Kubernetes templates:

```bash
bash codex.sh
```

Optional flags:
- `--skip-docker` (only generate env + Kubernetes manifests)
- `--clone <repo-url>` (clone an external source snapshot before setup)

Output artifacts:
- `.env.enterprise`
- `k8s/generated/api.yaml`
- `k8s/generated/worker.yaml`
- `k8s/generated/hpa.yaml`
- `k8s/generated/postgres.yaml`
- `k8s/generated/redis.yaml`

## 2) Full Config

Installer-generated files:
- `.env`
- `backend/api/api.env`
- `backend/worker/worker.env`
- `infra/certs/fullchain.pem`
- `infra/certs/privkey.pem`

Before production launch:
1. Replace placeholder values (for example `OPENAI_API_KEY`).
2. Rotate generated secrets if required by your policy.
3. Verify DNS points to your host (`app.<domain>`, `api.<domain>`).

## 3) Full Deploy

### Docker Compose deploy
```bash
bash scripts/run-stack.sh up
```

### Image + Kubernetes deploy
```bash
bash scripts/deploy-images.sh --registry ghcr.io/your-org/zlinebot-automos --tag v1.0.0
```

Optional flags:
- `--skip-push`
- `--skip-apply`

## 4) Full Starter / Runtime operations

```bash
bash scripts/run-stack.sh up
bash scripts/run-stack.sh ps
bash scripts/run-stack.sh logs api
bash scripts/run-stack.sh restart
bash scripts/run-stack.sh down
```

For systemd-driven lifecycle on installed servers:
```bash
sudo bash start-zLineBot-automos.sh install --domain example.com --cert-email ops@example.com
sudo bash start-zLineBot-automos.sh status
sudo bash start-zLineBot-automos.sh logs
```

## Health and endpoints

- Stack health: `https://api.<domain>/api/health`
- API auth: `POST /api/register`, `POST /api/login`
- Leads: `GET /api/leads`, `PATCH /api/leads/{lead_id}`
- Campaigns: `POST /api/broadcast`, `GET /api/campaigns`
- LINE webhook: `POST /webhook/{tenant_id}`

## Documentation

- [CHANGELOG.md](./CHANGELOG.md)
- [CONTRIBUTING.md](./CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
- [SECURITY.md](./SECURITY.md)
- [LICENSE](./LICENSE)
- [FEATURES.md](./FEATURES.md)

## 5) AUTONOMOS enterprise add-on

For the isolated enterprise scaffold (AI + Redis memory + trading modules), run:

```bash
bash scripts/zlinebot_autonomos.sh
```

Documentation: [docs/autonomos-enterprise-upgrade.md](./docs/autonomos-enterprise-upgrade.md)

## Documentation Refresh — 2026-03-26 (UTC)

- Marked the top-level operator guide as reviewed during the deep-scan documentation pass.
- Audit scope: repository-wide markdown and operational-documentation verification pass.
