# Release Readiness Scan

## Current state

### Working foundations
- Root monorepo/workspace setup for `frontend` and `landing` via the root `package.json`.
- Primary stack composition for API, worker, Postgres, Redis, Kafka, NGINX, and optional Cloudflared in `docker-compose.yml`.
- Basic FastAPI auth/chat endpoints in `backend/api/main.py`.
- Background Kafka-to-Postgres worker flow in `backend/worker/worker.py`.
- SQL bootstrap for users/messages in `backend/db/init.sql`.
- Static admin/user/devops panels and NGINX routing under `infra/`.

### Release blockers found during scan
1. Both Vite apps were missing root `index.html` entry files, so `npm run build:frontend` and `npm run build:landing` failed.
2. There are no automated tests yet for frontend, API, worker, or end-to-end flows.
3. Authentication is placeholder-grade: `/api/register` does not persist users and `/api/login` signs a token without validating stored credentials.
4. The chat endpoint is currently an echo response rather than a production AI workflow.
5. There is no documented production release checklist covering env vars, smoke tests, rollback, and backup validation.

## What was fixed now
- Added Vite-compatible root `index.html` entry files for both `frontend/` and `landing/` so production builds resolve correctly.
- Added a root `.gitignore` to keep generated dependencies and build output out of Git.

## Highest-impact next implementation steps

### P0: Must complete before a final release
1. Replace placeholder auth with real persistence, password hashing, and credential verification.
2. Add automated tests:
   - frontend build + smoke tests
   - FastAPI endpoint tests
   - worker unit/integration tests
   - Docker Compose smoke test
3. Implement a real `/api/chat` service path backed by the intended AI provider or job queue.
4. Create a production env template and release checklist.
5. Run a full stack validation on Docker Compose, including NGINX routing and healthchecks.

### P1: Strongly recommended before GA
1. Add structured logging and request IDs across API, worker, and NGINX.
2. Add database migrations instead of relying only on bootstrap SQL.
3. Add token verification/authorization middleware for protected endpoints.
4. Add CI for frontend builds, Python validation, and IaC policy checks.
5. Add monitoring dashboards and alert thresholds for API, worker, DB, Redis, and Kafka.

### P2: Finish quality and operations
1. Add user flows for dashboard/account state after login.
2. Add error pages, loading states, and API timeout handling in the frontend.
3. Add secrets management guidance for production deployment.
4. Add backup/restore drill documentation and recovery validation.
5. Add versioned release notes tied to deploy artifacts.

## Suggested release sequence
1. Finish auth and chat implementation.
2. Add tests and CI gates.
3. Validate local Docker Compose deployment end to end.
4. Lock environment/configuration docs.
5. Cut a release candidate and run a smoke checklist.
6. Ship GA after monitoring and rollback are verified.
