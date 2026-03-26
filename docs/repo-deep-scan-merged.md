# Repository Deep Scan (Merged View)

Last scanned: 2026-03-25 (UTC)

## 1) High-level inventory

The repository currently contains a **multi-surface platform** with infrastructure, backend API/worker services, web/mobile clients, and separate enterprise/quant extensions.

### Main areas discovered

- Core product stack:
  - `backend/api` (FastAPI)
  - `backend/worker` (Kafka/background processing)
  - `frontend` (React CRM)
  - `landing` (marketing site)
- Infra and deployment:
  - `docker/`, `infra/`, `k8s/`, `infrastructure/`, `installer/`, `scripts/`
- Enterprise/autonomous extensions:
  - `autonomos/`
  - `zBAutomos/`
  - `ai/`, `ai-agent/`, `rl/`, `execution/`, `portfolio/`, `investor/`, `marketplace/`
- Alternate/legacy service surfaces:
  - `backend-node/`
  - `api/`
  - `api-gateway/`
  - `worker/`

## 2) Language and file-shape summary

Scan snapshot (excluding `.git` and `node_modules` trees):

- Total files: **247**
- Most common file types:
  - `.js`: 68
  - `.py`: 23
  - `.sh`: 22
  - `.jsx`: 22
  - `.ts`: 20
  - `.md`: 17
  - `.yaml`: 15

Interpretation: this is a polyglot repo with significant shell + JavaScript + Python operational surface.

## 3) Runtime/build entrypoints (merged)

### JavaScript workspace root

- Root `package.json` defines workspaces for `frontend` and `landing`.
- Root scripts include:
  - `dev:frontend`, `build:frontend`
  - `dev:landing`, `build:landing`
  - `stack:up`, `stack:down`

### Python dependency surfaces

- `backend/api/requirements.txt` includes FastAPI, SQLAlchemy, Redis, Kafka, Stripe and test tooling.
- `backend/worker/requirements.txt` includes Kafka, SQLAlchemy, Redis, and requests.

## 4) Consolidation map ("merge all in" plan)

This section merges the repo into one actionable operational model without deleting code yet.

### A. Canonical production path

Treat these as canonical unless a migration decision is made:

1. **API**: `backend/api`
2. **Worker**: `backend/worker`
3. **UI**: `frontend`
4. **Marketing**: `landing`
5. **Infra orchestration**: `docker/` + `scripts/` + `k8s/`

### B. Candidate overlap zones to normalize

- `backend/worker` vs top-level `worker/`
- `backend/api` vs top-level `api/`
- `autonomos/` vs `zBAutomos/`
- `infra/` vs `infrastructure/`
- `backend-node/` vs Python API stack (parallel webhook/server implementation)

### C. Proposed merge policy

- Mark one directory as **source-of-truth** for each domain.
- Move alternate implementations behind explicit labels:
  - `legacy/` for deprecated but retained code.
  - `experimental/` for incubating modules.
- Keep deployment scripts aligned to only canonical services.
- Add CI checks to block references to non-canonical paths once migration begins.

## 5) Immediate next-step checklist

1. Declare canonical owners for API/worker/frontend/infra paths.
2. Add a `docs/repo-map.md` with ownership + status (`canonical`, `legacy`, `experimental`).
3. Update scripts and compose manifests to stop starting duplicate service paths.
4. Migrate or archive overlap directories in small PRs.
5. Add CI validation for canonical path usage and dependency hygiene.

## 6) Validation run performed

- Worker tests were executed successfully:
  - `pytest backend/worker/tests -q`
  - Result: `4 passed`

---

If you want, the next pass can be an **automated canonicalization PR** that:

- writes a machine-readable ownership manifest,
- tags overlap directories in-place,
- and updates launch scripts to a single canonical stack entrypoint.

## Documentation Refresh — 2026-03-26 (UTC)

- Extended the deep-scan record with a fresh repository-wide documentation audit checkpoint.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

