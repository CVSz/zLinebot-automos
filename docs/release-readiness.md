# Release Readiness Scan

## Current state

### Working foundations now in place
- Root monorepo/workspace setup for `frontend` and `landing` via the root `package.json`.
- Primary stack composition for API, worker, Postgres, Redis, Kafka, NGINX, and optional Cloudflared in `docker-compose.yml`.
- Multi-tenant FastAPI CRM API in `backend/api/main.py`.
- Kafka worker flow in `backend/worker/worker.py` for async campaign sends.
- Tenant-aware SQL bootstrap for tenants/users/leads/templates/campaigns/messages in `backend/db/init.sql`.
- React CRM dashboard with login and workspace state in `frontend/src/pages/DashboardPage.jsx`.

### What is no longer a blocker
1. Auth is now persisted and validated with hashed passwords and bearer tokens.
2. The primary frontend has a real post-login dashboard instead of only landing/auth entrypoints.
3. The API now exposes actual CRM workflows for leads, templates, campaigns, analytics, and billing hooks.
4. The worker now performs campaign delivery work rather than only recording inbound placeholder messages.

## Remaining release blockers

1. LINE signature verification is still only stubbed, so webhook authenticity is not yet enforced.
2. Google Sheets sync remains a stub and is not connected to real credentials or background retries.
3. There are still no automated frontend tests, worker tests, or end-to-end Docker Compose checks.
4. Queue delivery has no explicit retry/backoff controls or operator dashboard for failed campaign sends.
5. There is no production release checklist covering environment setup, rollback, billing verification, and backup drills.

## Recommended next steps

### P0: Must complete before a final release
1. Implement real LINE webhook signature validation and tenant secret management.
2. Replace the sheets sync stub with a production integration and failure handling strategy.
3. Add automated tests for:
   - frontend dashboard smoke coverage
   - CRM API endpoints beyond auth
   - worker broadcast processing
   - full Docker Compose health and routing
4. Create an explicit production env template and release checklist.
5. Run a complete end-to-end validation of API, worker, Kafka, Redis, Postgres, and NGINX under Docker Compose.

### P1: Strongly recommended before GA
1. Add database migrations instead of relying only on bootstrap SQL.
2. Add structured logging, request IDs, and audit events across API and worker services.
3. Add retry/backoff and rate-aware batching for outbound LINE delivery.
4. Add monitoring dashboards and alert thresholds for queue lag, campaign failures, and webhook error rates.
5. Add admin tooling for tenant provisioning, LINE token management, and campaign troubleshooting.

### P2: Finish quality and operations
1. Add richer billing/account pages in the dashboard.
2. Add better empty/error/loading states in the CRM UI.
3. Add backup/restore drill documentation and recovery validation.
4. Add CI gates for Python validation, frontend build/test, and IaC policy checks.
5. Add versioned release notes tied to deploy artifacts.

## Suggested release sequence
1. Complete webhook security and Google Sheets integration.
2. Add missing automated coverage and Compose smoke tests.
3. Validate staging with real queue, billing, and LINE credentials.
4. Lock production environment/configuration docs.
5. Cut a release candidate and run the checklist.
6. Ship GA after monitoring and rollback are verified.
