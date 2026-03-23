# zLineBot-automos

zLineBot-automos is now organized as a single root-level full-stack project.
The repository has been flattened so the main application services, deployment assets,
and auxiliary source modules all live directly under the project root instead of being
split between `zeaz-ultra/` and `zeaz-ultra-pack/`.

## Root Project Layout

```text
/workspace/zLine
├─ frontend/         # Primary React + Vite web app
├─ backend/          # FastAPI API, worker, and database bootstrap
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

1. Generate the root runtime environment.

```bash
./gen-secrets.sh zlinebot-automos.local admin@zlinebot-automos.local
```

2. Start the stack from the repository root.

```bash
docker compose up -d --build
```

3. Useful local entrypoints:

- Web app: `https://<host>/`
- API health: `https://<host>/api/health`
- Admin panel: `https://<host>/admin/`
- User panel: `https://<host>/user/`
- DevOps panel: `https://<host>/devops/`

## Supporting Modules

- `landing/`: preserved React landing app source.
- `backend-node/`: preserved Express checkout + webhook sample.
- `api/`, `billing/`, `worker/`, `docker/`, `k8s/`, and `monitoring/`: preserved supporting services and deployment assets.
- `infrastructure/`: OPA/Kyverno policy tooling for Kubernetes manifests.

## Documentation Index

- [FEATURES.md](./FEATURES.md)
- [CHANGELOG.md](./CHANGELOG.md)
- [infrastructure/README.md](./infrastructure/README.md)
- [infra/cloudflared/README.md](./infra/cloudflared/README.md)
- [infra/certs/README.md](./infra/certs/README.md)
