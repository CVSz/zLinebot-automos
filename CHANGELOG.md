# Changelog

## 2026-03-24

### Fixed
- Fixed `scripts/deploy-images.sh` calling a non-existent script by replacing it with a complete deploy workflow that correctly builds, optionally pushes, and optionally applies Kubernetes manifests.
- Fixed installer behavior so `installer/install.sh` only requires root in `--mode system`, while enforcing `--skip-deps` for `--mode project`.

### Added
- Added `scripts/run-stack.sh` as a unified runtime starter for `up/down/restart/logs/ps` operations.
- Added repository governance and security docs: `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `LICENSE`, and `SECURITY.md`.

### Changed
- Expanded `scripts/build-images.sh` to support configurable image registry and tag parameters.
- Refreshed `README.md` with full installer/config/deploy/starter guidance for production-ready operations.

## 2026-03-23

### Added
- Added a multi-tenant CRM implementation to the primary FastAPI stack with tenant, lead, template, campaign, and message persistence.
- Added tenant-scoped JWT auth, password hashing, LINE webhook ingestion, lead scoring, revenue stats, template management, and Stripe billing hooks.
- Added async campaign delivery support through Kafka-backed broadcast queue publishing and worker-side LINE push processing.
- Added a `/dashboard` CRM frontend with workspace login flow, pipeline views, analytics cards, template management, and campaign controls.

### Changed
- Expanded the Postgres bootstrap SQL from a minimal users/messages schema into a tenant-aware CRM schema.
- Updated repository documentation to describe the current CRM automation architecture, endpoints, and release posture.
- Preserved the flattened root-level project structure introduced earlier for all supporting source modules and infrastructure assets.

## Documentation Refresh — 2026-03-26 (UTC)

- Added a documentation maintenance entry for the 2026-03-26 full-markdown refresh.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

