# zLineBot-automos Feature Inventory

## 1) Primary CRM application

### Frontend (`frontend/`)
- React + Vite dashboard route at `/dashboard`.
- Workspace signup and login flows.
- Persisted session handling after login.
- KPI cards for lead count, hot leads, revenue, and conversion rate.
- Lead pipeline board grouped by status.
- Template management UI.
- Broadcast composer with campaign history.
- Billing upgrade trigger for Stripe checkout.

### API (`backend/api/`)
- Multi-tenant schema models for `Tenant`, `User`, `Lead`, `Template`, `Campaign`, and `Message`.
- Password hashing with scrypt and JWT-based login.
- Tenant-scoped authorization and `X-Tenant-Id` support.
- LINE webhook ingestion with lead extraction, scoring, and stage assignment.
- Ollama-compatible reply generation with fallback responses.
- Lead listing, updates, stats, and daily revenue endpoints.
- Template and campaign endpoints.
- Stripe checkout session and webhook handlers.
- Redis-backed rate limiting with in-memory fallback.
- Kafka-backed broadcast queue publisher with sync fallback if the queue is unavailable.

### Worker (`backend/worker/`)
- Kafka consumer for inbound message events.
- Kafka consumer for queued broadcast campaigns.
- LINE push delivery for campaign recipients.
- Campaign sent-count updates.
- Message persistence for outbound campaign sends.
- DLQ fallback on processing errors.

### Database bootstrap (`backend/db/init.sql`)
- Tenant-aware schema for:
  - `tenants`
  - `users`
  - `leads`
  - `templates`
  - `campaigns`
  - `messages`
- Tenant/status/message indexes for faster CRM lookups.

## 2) Runtime stack and infrastructure

- Root `docker-compose.yml` orchestrates API, worker, Postgres, Redis, Kafka, NGINX, and optional Cloudflared.
- `infra/` contains reverse proxy, cert, tunnel, panel, backup, and monitoring support assets.
- `k8s/` and `infrastructure/` preserve Kubernetes and policy tooling for future deployment paths.

## 3) Preserved supporting source modules

- `landing/`: original landing page React app.
- `backend-node/`: Express checkout and webhook demo backend.
- `api/`: auxiliary FastAPI + Stripe integration example.
- `ai-agent/`: automation/agent module.
- `billing/`: standalone Stripe helper utilities.
- `worker/`: additional worker implementation.
- `docker/`: extra Dockerfiles.
- `monitoring/`: Prometheus configuration.
- `security/`: shared middleware/security helpers.
- `viral-content/`: content templates and TikTok scripting material.

## 4) Operational tooling

- `installer/install.sh`: shared modular installer that prepares the full stack in system or project mode.
- `installer/lib/*.sh`: reusable shell modules for logging, runtime setup, env generation, TLS, and stack staging.
- `zeaz_ai_full_stack_installer.sh`: compatibility wrapper for system installs into `/opt/zLineBot-automos`.
- `ubuntu_stack_installer.sh`: compatibility wrapper for preparing a local project copy in `./zlinebot-automos-stack`.
- `start-zLineBot-automos.sh`: installs and manages the root Docker Compose stack as a systemd service.
- `infrastructure/scripts/check-iac-policy.sh`: validates root `k8s/*.yaml` manifests.
- `infrastructure/scripts/auto-fix-pipeline.sh`: applies safe formatting/permission remediation.

## 5) AUTONOMOS quant + AI expansion

- `autonomos/trading/rl_agent.js`: RL-lite Q-learning policy with indicator-driven state bucketing.
- `autonomos/trading/copyTrading.js`: follower mapping, copy propagation, and bot ranking utilities.
- `autonomos/trading/market_maker.js`: spread-based market making quotes with inventory bounds.
- `autonomos/trading/arbitrage.js`: cross-venue edge detector with fee-aware threshold checks.
- `autonomos/analytics/*.js`: Sharpe, drawdown, win-rate, VaR, PnL, and exposure metrics helpers.
- `rl/`: PyTorch DQN scaffold (`model.py`, `agent.py`, `train.py`, `infer.py`) for deeper RL workflows.
- `mobile/App.js`: React Native starter surface for mobile trading telemetry views.
- `deploy.sh`: scripted enterprise deployment with build, apply, and autoscale steps.
