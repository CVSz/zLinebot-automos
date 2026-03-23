# Changelog

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
