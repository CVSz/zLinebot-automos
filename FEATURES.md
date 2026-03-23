# Full Feature Documentation

This document consolidates the complete feature set currently available across all projects in this repository.

## 1) ZEAZ Ultra Landing (`zeaz-ultra/`)

### Product/UX Features

- **Landing Hero + CTA flow**
  - Upgrade CTA triggers Stripe checkout creation via `/api/create-checkout`.
  - Free Trial CTA smooth-scrolls to in-page demo chat section.
- **Feature cards section**
  - Live Demo API positioning.
  - Auto money funnel narrative (trial → paid → upsell).
  - Viral content readiness messaging.
- **Live Demo Chat UI**
  - Message composer with validation.
  - Loading/error states.
  - Displays API response from `/api/chat`.
- **Viral Content Assets**
  - Ready-to-use TikTok/Shorts/Reels scripts in markdown.

### Backend/API Features

- **Stripe Checkout Session API** (`POST /api/create-checkout`)
  - Subscription mode checkout session creation.
  - Uses `STRIPE_SECRET_KEY` and `STRIPE_PRICE_ID`.
- **Demo Chat API** (`POST /api/chat`)
  - Accepts a message payload.
  - Returns a simulated AI response for demo/sales flow.
- **Stripe Webhook Listener** (`POST /webhook`)
  - Verifies event signatures with `STRIPE_WEBHOOK_SECRET`.
  - Handles `checkout.session.completed` and logs paid customer event.

### Runtime/Build Features

- Vite dev/build/preview scripts.
- Node backend and webhook scripts via npm.
- Tailwind + PostCSS styling pipeline.

---

## 2) ZEAZ Ultra Pack (`zeaz-ultra-pack/`)

### Frontend Features

- **Route-aware pages** for:
  - Landing (`/`)
  - Signup (`/signup`)
  - Login (`/login`)
- **Landing composition blocks**
  - Hero
  - Features
  - Viral templates
  - Chat demo
  - CTA component
- **Auth flows (frontend wiring)**
  - Register/login forms posting to API endpoints.
- **Chat demo integration**
  - Sends user message to `/api/chat` and renders server response.

### API Features (FastAPI)

- `GET /health` and `GET /api/health`: service health payload.
- `POST /api/register`: validates username length and returns success payload.
- `POST /api/login`: validates credentials and mints JWT bearer token.
- `POST /api/chat`: validates message and returns echo reply.

### Worker + Data Pipeline Features

- **Kafka Consumer** for `events.messages`.
- **Database persistence** into Postgres `messages` table.
- **DLQ fallback**
  - Failed processing published to `events.dlq`.
- **Resilience pattern**
  - Catches processing exceptions and retries loop with backoff sleep.

### Infrastructure Features (Docker Compose)

- **Services included**
  - API, Worker, Postgres, Redis, Zookeeper, Kafka, NGINX, optional Cloudflared.
- **Operational hardening**
  - Health checks per service.
  - Restart policies.
  - CPU/memory resource caps.
- **Network topology**
  - Internal-only backend network.
  - Public network for ingress components.
- **TLS ingress**
  - NGINX endpoint for HTTP/HTTPS.
  - Self-signed certificate fallback if custom certs absent.
- **Optional Cloudflare tunnel profile**
  - Supports wildcard host routing (`*.zeaz.dev`) plus `cme.zeaz.dev`.

### Operations Features

- **Secret bootstrap script**: `gen-secrets.sh`
- **Health monitoring script**: `infra/monitor/health.sh`
- **Encrypted backup script**: `infra/backup/backup.sh`
  - AES-256 encrypted dump output.
  - SHA-256 checksum artifact.

---

## 3) Infrastructure Policy Toolkit (`infrastructure/`)

### Policy & Compliance Features

- **OPA (Conftest) Kubernetes policy validation**
  - Uses `policies/opa/k8s-security.rego`.
- **Kyverno policy validation**
  - Uses `policies/kyverno/require-baseline.yaml`.
- **IaC check orchestration script**
  - `scripts/check-iac-policy.sh`.

### CI Self-Healing Features

- `scripts/auto-fix-pipeline.sh` for safe automatic fixes:
  - Script permission corrections.
  - YAML whitespace normalization.

---

## Feature Status Snapshot

| Area | Status | Notes |
|---|---|---|
| Landing funnel UX | ✅ Available | CTA + demo flow implemented |
| Stripe checkout + webhook | ✅ Available | DB paid-role update still TODO in webhook |
| Auth API (register/login) | ✅ Available | JWT issued on login |
| Chat demo APIs | ✅ Available | Demo/echo behavior implemented |
| Event pipeline (Kafka → worker → DB) | ✅ Available | DLQ fallback included |
| TLS reverse proxy | ✅ Available | Self-signed fallback + custom cert support |
| Cloudflare tunnel profile | ✅ Optional | Enabled through compose profile |
| Backup + monitoring scripts | ✅ Available | AES-256 backups + health checks |
| IaC policy validation | ✅ Available | OPA + Kyverno baselines included |

## Known Gaps / Backlog Indicators

- Stripe webhook payment completion currently logs output and includes TODO for DB user role promotion.
- Demo chat responses are placeholder/echo behavior (no production LLM integration yet).
- Some docs are project-scoped; root-level docs were added to unify visibility.
