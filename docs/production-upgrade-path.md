# Production Upgrade Path (Local VM → Cloud)

This document maps a practical migration path using the existing repository layout.

## Zero-cost local baseline

- **API**: Node.js/Express (`autonomos/api`).
- **Execution**: smart execution, TWAP slicing, and best-routing (`autonomos/execution/engine.js`).
- **Data pipeline**: websocket tick collection + Redis buffering + batched flush (`autonomos/data`).
- **Compliance**: starter KYC submission + audit log hooks (`autonomos/kyc/service.js`).
- **Reporting**: PDF report generation for investor snapshots (`autonomos/reporting/report.js`).

## Suggested runtime wiring

1. Start API with PM2 (`node autonomos/api/server.js`).
2. Run tick collector in a separate PM2 process.
3. Run tick storage worker in a separate PM2 process.
4. Enable Nginx reverse proxy + TLS termination.

## Cloud lift plan

1. Move Redis/Postgres to managed services.
2. Containerize API/worker processes and deploy behind a load balancer.
3. Store audit logs and reports in object storage.
4. Add managed observability and alerting.

## Documentation Refresh — 2026-03-26 (UTC)

- Reconfirmed migration sequencing against active runtime directories (`backend`, `frontend`, `k8s`, `infrastructure`).
- Audit scope: repository-wide markdown and operational-documentation verification pass.

