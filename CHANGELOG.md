# Changelog

## 2026-03-23

### Changed
- Flattened the repository into a single root-level project structure named `zLineBot-automos`.
- Promoted the full-stack app from the former nested package into root directories: `frontend/`, `backend/`, `infra/`, `.env.example`, and `gen-secrets.sh`.
- Preserved additional source modules as root-level directories: `landing/`, `backend-node/`, `api/`, `ai-agent/`, `billing/`, `docker/`, `k8s/`, `monitoring/`, `security/`, `viral-content/`, `worker/`, and `scripts/`.
- Added a root `docker-compose.yml` so installation and service management operate from the repository root.
- Updated project metadata, HTML titles, API titles, documentation, and infrastructure references from legacy ZEAZ naming to `zLineBot-automos`.
