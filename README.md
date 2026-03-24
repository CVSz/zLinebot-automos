# zLineBot-automos

zLineBot-automos is a root-level full-stack CRM and LINE automation workspace.
The current stack combines a React dashboard, a FastAPI multi-tenant CRM API,
Kafka-backed broadcast delivery, Postgres/Redis infrastructure, and the preserved
supporting modules that were already living in this repository.

## What the primary stack now does

### CRM + automation capabilities
- Multi-tenant workspaces with tenant-scoped users and JWT login.
- Lead capture from LINE webhook payloads.
- Lead scoring and funnel stages: `new`, `cold`, `warm`, `hot`, `closed`.
- Daily revenue and conversion analytics.
- Campaign broadcasts with async queue delivery through Kafka + worker.
- Message templates and campaign reply tracking.
- Stripe checkout + subscription webhook hooks.
- Redis-backed rate limiting with in-memory fallback.
- Ollama-compatible sales reply generation with rule-based fallback.

### Main runtime services
- `frontend/`: React + Vite CRM dashboard and auth flows.
- `backend/api/`: FastAPI API with auth, webhook, leads, analytics, billing, and template endpoints.
- `backend/worker/`: Kafka consumer that pushes queued campaign deliveries to LINE and persists message/campaign updates.
- `backend/db/init.sql`: bootstrap schema for tenants, users, leads, templates, campaigns, and messages.
- `docker-compose.yml`: root stack for API, worker, Postgres, Redis, Kafka, NGINX, and optional Cloudflared.

## Root Project Layout

```text
/workspace/zLine
├─ frontend/         # Primary React + Vite CRM dashboard
├─ backend/          # FastAPI API, Kafka worker, and DB bootstrap
├─ infra/            # Docker, NGINX, backup, health, and Cloudflared assets
├─ docker-compose.yml# Root stack entrypoint used by installers/service scripts
├─ landing/          # Legacy landing experience preserved as a root module
├─ backend-node/     # Node checkout/webhook demo backend preserved as a root module
├─ api/              # Auxiliary FastAPI + Stripe demo API module
├─ ai-agent/         # Agent integration code
├─ billing/          # Billing/Stripe helpers
├─ docker/           # Extra image definitions
├─ k8s/              # Kubernetes manifests
├─ monitoring/       # Monitoring configuration
├─ security/         # Shared security middleware/utilities
├─ scripts/          # Image build/deploy helper scripts
├─ viral-content/    # Marketing content assets
└─ infrastructure/   # IaC policy tooling and CI remediation scripts
```

## Quick Start

### 1. Prepare local secrets

```bash
./gen-secrets.sh zeaz.dev admin@zeaz.dev
```

### 2. Start the full stack

```bash
docker compose up -d --build
```

### 3. Or use the installer

```bash
sudo bash installer/install.sh --mode project --domain zeaz.dev --app-dir ./zlinebot-automos-stack
```

## Useful local entrypoints

- Web app / landing: `https://app.<domain>/`
- API health: `https://api.<domain>/api/health`
- CRM auth API: `https://<host>/api/register` and `https://<host>/api/login`
- Tenant webhook: `https://api.<domain>/webhook/<tenant_id>`
- Admin panel: `https://app.<domain>/admin/`
- User panel: `https://app.<domain>/user/`
- DevOps panel: `https://app.<domain>/devops/`

## Core API surface

### Auth + tenant bootstrap
- `POST /api/register` → create an admin user and tenant workspace.
- `POST /api/login` → issue tenant-scoped bearer token.
- `GET /api/me` → return current user profile.

### CRM operations
- `POST /webhook/{tenant_id}` → ingest LINE messages into lead + message records.
- `GET /api/leads` → list tenant leads.
- `PATCH /api/leads/{lead_id}` → update pipeline status or price.
- `GET /api/stats` → aggregate funnel + revenue metrics.
- `GET /api/revenue/daily` → daily revenue trend.

### Campaigns + templates
- `POST /api/templates` / `GET /api/templates`
- `POST /api/broadcast` / `GET /api/campaigns`

### Billing
- `POST /api/billing/checkout`
- `POST /stripe/webhook`

## Environment notes

The current API and worker expect these environment variables in production:

- `DATABASE_URL`
- `JWT_SECRET_CURRENT`
- `KAFKA_BROKER`
- `REDIS_URL` (optional but recommended)
- `OLLAMA_URL` and `OLLAMA_MODEL` (optional)
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID`
- `APP_BASE_URL`
- `APP_HOST`
- `API_HOST`
- `WILDCARD_HOST` (optional)
- `CORS_ALLOW_ORIGINS`

Tenant-specific LINE credentials are stored in the `tenants.line_channel_token` and `tenants.line_channel_secret` columns.

## Supporting Modules

- `landing/`: preserved React landing app source.
- `backend-node/`: preserved Express checkout + webhook sample.
- `api/`, `billing/`, `worker/`, `docker/`, `k8s/`, and `monitoring/`: preserved supporting services and deployment assets.
- `infrastructure/`: OPA/Kyverno policy tooling for Kubernetes manifests.

## Documentation Index

- [FEATURES.md](./FEATURES.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [docs/release-readiness.md](./docs/release-readiness.md)
- [infrastructure/README.md](./infrastructure/README.md)
- [infra/cloudflared/README.md](./infra/cloudflared/README.md)
- [infra/certs/README.md](./infra/certs/README.md)
