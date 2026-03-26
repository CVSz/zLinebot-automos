# zLineBot-AUTOMOS Final Enterprise Upgrade

This package adds a production-grade enterprise scaffold for:

- API gateway ingress service.
- Affiliate referral service with idempotent rewards.
- AI bot marketplace purchase flow.
- Execution smart router with slippage control.
- Strategy optimizer and portfolio signal aggregation.
- Mobile websocket client with exponential reconnect.
- Container packaging via Docker Compose + NGINX reverse proxy.
- Kubernetes deployment + HPA manifests for API autoscaling.

## Project Structure (new)

```text
api-gateway/server.ts
core/affiliate/service.ts
marketplace/service.ts
execution/smartRouter.ts
ai/optimizer.ts
portfolio/engine.ts
mobile/App.tsx
docker/docker-compose.enterprise.yml
nginx/enterprise.conf
k8s/enterprise-api-deployment.yaml
k8s/enterprise-hpa.yaml
```

## Quick Start (enterprise package)

```bash
docker compose -f docker/docker-compose.enterprise.yml up --build
```

## Notes

- Keep live order execution disabled in non-production environments.
- Add JWT validation middleware and payment checks before enabling purchases.
- Validate optimizer outputs using walk-forward tests to mitigate overfitting.

## Documentation Refresh — 2026-03-26 (UTC)

- Marked enterprise scaffold guidance as reviewed against current folder inventory.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

