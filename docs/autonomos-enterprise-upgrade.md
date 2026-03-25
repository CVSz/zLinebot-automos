# zLineBot-AUTOMOS Enterprise Upgrade Add-on

This repository already ships a production-oriented stack (FastAPI API, worker, Docker, and deployment scripts). This add-on introduces a **separate, non-destructive enterprise playground** for:

- LINE webhook + AI response flow
- Redis chat memory
- Trading strategy/risk modules
- Agent orchestrator scaffolding

## Why this add-on is separate

The add-on is intentionally isolated under `autonomos/` so it does not overwrite or break the current backend/frontend services.

## Bootstrap

```bash
bash scripts/zlinebot_autonomos.sh
```

The script will:

1. Create `autonomos/` module scaffolding.
2. Generate `.env.autonomos` with safe defaults (`LIVE_TRADING=false`).
3. Install required Node packages at repository root.
4. Skip files that already exist (idempotent behavior).

## Run locally

```bash
cp .env.autonomos .env
node autonomos/api/server.js
```

> Keep `LIVE_TRADING=false` until simulation/backtesting and observability are verified.

## Suggested next steps

1. Add historical backtesting runner before enabling live orders.
2. Add centralized logging + alerting around trading actions.
3. Add API authentication and tenant isolation for `/webhook`.
4. Add dashboard pages consuming runtime telemetry from this module.
