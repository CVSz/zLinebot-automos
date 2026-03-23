# zLine Repository Overview

zLine is a multi-project repository containing three major deliverables:

1. **ZEAZ Ultra Landing** (`zeaz-ultra/`): lightweight React + Vite landing experience with Stripe checkout and demo API.
2. **ZEAZ Ultra Pack** (`zeaz-ultra-pack/`): deploy-ready full-stack platform (React + FastAPI + worker + Kafka/Redis/Postgres + NGINX + optional Cloudflared).
3. **Infrastructure Policy Toolkit** (`infrastructure/`): IaC policy checks and safe CI auto-remediation scripts.

For a complete feature inventory, see **[FEATURES.md](./FEATURES.md)**.

## Repository Structure

```text
/workspace/zLine
├─ zeaz-ultra/          # Landing + Stripe checkout + demo chat + viral content scripts
├─ zeaz-ultra-pack/     # Full stack app + infra + backup + health + cloudflare tunnel support
└─ infrastructure/      # OPA + Kyverno policy checks and CI auto-fix scripts
```

## Quick Start by Project

### 1) ZEAZ Ultra Landing

```bash
cd zeaz-ultra
npm install
npm run dev
```

Optional backend services:

```bash
npm run backend
npm run webhook
```

### 2) ZEAZ Ultra Pack

```bash
cd zeaz-ultra-pack
./gen-secrets.sh zeaz.dev admin@zeaz.dev
cd infra
docker compose --env-file ../.env up -d --build
```

### 3) Infrastructure Policy Toolkit

```bash
./infrastructure/scripts/check-iac-policy.sh
./infrastructure/scripts/auto-fix-pipeline.sh
```

## Core Capabilities (High-Level)

- Marketing landing flows with CTA funnels and interactive chat demo.
- Stripe subscription checkout + webhook handling.
- FastAPI auth and chat endpoints.
- Event-driven worker processing with Kafka and DLQ fallback.
- Containerized platform with health checks, resource limits, and network segmentation.
- NGINX reverse proxy with TLS, route segmentation, and optional Cloudflare Tunnel ingress.
- Operational scripts for encrypted backups and health monitoring.
- CI policy enforcement for Kubernetes security baselines.

## Documentation Index

- [FEATURES.md](./FEATURES.md): Full feature-by-feature documentation.
- [CHANGELOG.md](./CHANGELOG.md): Consolidated project changelog.
- [zeaz-ultra/README.md](./zeaz-ultra/README.md): Landing app details.
- [zeaz-ultra-pack/README.md](./zeaz-ultra-pack/README.md): Deploy-ready stack details.
- [infrastructure/README.md](./infrastructure/README.md): Policy tooling details.
