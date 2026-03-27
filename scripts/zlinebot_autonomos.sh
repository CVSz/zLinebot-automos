#!/usr/bin/env bash
set -euo pipefail

# zLineBot-AUTOMOS enterprise add-on bootstrap
# - Non-destructive: does not overwrite existing backend/frontend structure
# - Safe-by-default: writes LIVE_TRADING=false in .env.autonomos

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTONOMOS_DIR="${APP_ROOT}/autonomos"
ENV_FILE="${APP_ROOT}/.env.autonomos"

log() { printf "\n[%s] %s\n" "zlinebot-autonomos" "$*"; }

display_path() {
  local file="$1"
  python3 - "$APP_ROOT" "$file" <<'PY'
from pathlib import Path
import os
import sys

root = Path(sys.argv[1]).resolve()
path = Path(sys.argv[2]).resolve()
try:
    print(path.relative_to(root))
except ValueError:
    print(os.path.relpath(path, root))
PY
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

write_if_missing() {
  local file="$1"
  local content="$2"
  if [[ -f "$file" ]]; then
    log "skip existing $(display_path "$file")"
  else
    mkdir -p "$(dirname "$file")"
    printf "%s\n" "$content" >"$file"
    log "created $(display_path "$file")"
  fi
}

main() {
  ensure_cmd node
  ensure_cmd npm
  ensure_cmd python3

  log "Preparing enterprise add-on scaffold under ./autonomos"
  mkdir -p "${AUTONOMOS_DIR}"/{api,ai,memory,agents,trading,dashboard,ops}

  write_if_missing "${AUTONOMOS_DIR}/ai/chatgpt.js" 'import OpenAI from "openai";

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function askAI(input) {
  const response = await client.responses.create({
    model: process.env.OPENAI_MODEL || "gpt-5.3",
    input,
  });

  return response.output_text || "";
}
'

  write_if_missing "${AUTONOMOS_DIR}/memory/memory.js" 'import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://127.0.0.1:6379");

export async function saveMessage(userId, message) {
  await redis.lpush(`chat:${userId}`, message);
  await redis.ltrim(`chat:${userId}`, 0, 50);
}

export async function getRecentMessages(userId, limit = 10) {
  return redis.lrange(`chat:${userId}`, 0, limit - 1);
}
'

  write_if_missing "${AUTONOMOS_DIR}/trading/risk.js" 'export function riskControl(balance, price) {
  const riskPerTrade = Number(process.env.RISK_PER_TRADE || 0.01);
  const stopLossPercent = Number(process.env.STOP_LOSS_PCT || 0.02);

  if (!Number.isFinite(balance) || balance <= 0 || !Number.isFinite(price) || price <= 0) {
    return { amount: 0, stopLoss: 0 };
  }

  const amount = (balance * riskPerTrade) / price;
  const stopLoss = price * (1 - stopLossPercent);

  return { amount, stopLoss };
}
'

  write_if_missing "${AUTONOMOS_DIR}/trading/strategy.js" 'import { EMA, MACD, RSI } from "technicalindicators";

export function strategy(prices) {
  if (!prices || prices.length < 60) return "HOLD";

  const rsi = RSI.calculate({ period: 14, values: prices }).slice(-1)[0];
  const macd = MACD.calculate({
    values: prices,
    fastPeriod: 12,
    slowPeriod: 26,
    signalPeriod: 9,
    SimpleMAOscillator: false,
    SimpleMASignal: false,
  }).slice(-1)[0];
  const ema = EMA.calculate({ period: 50, values: prices }).slice(-1)[0];
  const last = prices[prices.length - 1];

  if (rsi < 30 && macd?.histogram > 0 && last > ema) return "BUY";
  if (rsi > 70 && macd?.histogram < 0 && last < ema) return "SELL";
  return "HOLD";
}
'

  write_if_missing "${AUTONOMOS_DIR}/trading/binance.js" 'import Binance from "binance-api-node";

const client = Binance({
  apiKey: process.env.BINANCE_API_KEY,
  apiSecret: process.env.BINANCE_SECRET,
});

export async function marketBuy(symbol, quantity) {
  return client.order({ symbol, side: "BUY", type: "MARKET", quantity });
}

export async function marketSell(symbol, quantity) {
  return client.order({ symbol, side: "SELL", type: "MARKET", quantity });
}
'

  write_if_missing "${AUTONOMOS_DIR}/trading/engine.js" 'import { marketBuy, marketSell } from "./binance.js";
import { riskControl } from "./risk.js";
import { strategy } from "./strategy.js";

export async function runTradingEngine({ prices, balance, symbol = "BTCUSDT" }) {
  const action = strategy(prices);
  if (!Array.isArray(prices) || prices.length === 0) {
    return { mode: "simulation", action: "HOLD", amount: 0, symbol, reason: "no_prices" };
  }

  const price = prices[prices.length - 1];
  if (!Number.isFinite(price) || price <= 0) {
    return { mode: "simulation", action: "HOLD", amount: 0, symbol, reason: "invalid_price" };
  }

  const { amount } = riskControl(balance, price);
  const live = String(process.env.LIVE_TRADING || "false") === "true";

  if (!live || amount <= 0) {
    return { mode: "simulation", action, amount, symbol, price };
  }

  if (action === "BUY") return marketBuy(symbol, amount);
  if (action === "SELL") return marketSell(symbol, amount);
  return { mode: "live", action: "HOLD", amount: 0, symbol, price };
}
'

  write_if_missing "${AUTONOMOS_DIR}/agents/orchestrator.js" 'export async function runAgents() {
  console.log("[agents] analyzing telemetry");
  console.log("[agents] tuning strategy candidates");
}
'

  write_if_missing "${AUTONOMOS_DIR}/api/server.js" 'import express from "express";
import { askAI } from "../ai/chatgpt.js";
import { getRecentMessages, saveMessage } from "../memory/memory.js";

const app = express();
app.use(express.json());

app.post("/webhook", async (req, res) => {
  try {
    const user = req.body?.userId || "line-user";
    const msg = req.body?.message || "hello";

    await saveMessage(user, msg);
    const history = await getRecentMessages(user);

    const reply = await askAI(history.reverse().join("\n"));
    return res.json({ reply });
  } catch (error) {
    console.error("[autonomos] webhook error", error);
    return res.status(500).json({ error: "internal_error" });
  }
});

const port = Number(process.env.PORT || 3300);
app.listen(port, () => console.log(`[autonomos] api listening on ${port}`));
'

  if [[ ! -f "$ENV_FILE" ]]; then
    cat >"$ENV_FILE" <<'ENV'
PORT=3300
OPENAI_API_KEY=
OPENAI_MODEL=gpt-5.3
LINE_CHANNEL_ACCESS_TOKEN=
LINE_CHANNEL_SECRET=
REDIS_URL=redis://127.0.0.1:6379
BINANCE_API_KEY=
BINANCE_SECRET=
RISK_PER_TRADE=0.01
STOP_LOSS_PCT=0.02
LIVE_TRADING=false
ENV
    log "created .env.autonomos (safe defaults: LIVE_TRADING=false)"
  else
    log "skip existing .env.autonomos"
  fi

  log "Installing optional Node dependencies in repository root"
  if npm install --no-fund --no-audit express ioredis openai technicalindicators binance-api-node >/dev/null; then
    log "dependency install complete"
  else
    log "dependency install skipped (registry/network policy); install manually when running in target host"
  fi

  log "Done. Next steps:"
  echo "  1) Fill .env.autonomos secrets"
  echo "  2) Start Redis"
  echo "  3) Run: node autonomos/api/server.js"
}

main "$@"
