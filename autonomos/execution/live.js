import { createClient, safeBuy, safeSell } from "../trading/binance_safe.js";

let client;

function getClient() {
  if (!client) {
    try {
      client = createClient();
    } catch {
      client = null;
    }
  }
  return client;
}

export async function executeTrade(signal, options = {}) {
  const symbol = options.symbol || "BTCUSDT";
  const quantity = Number(options.quantity || process.env.DEFAULT_ORDER_SIZE || 0.001);
  const live = String(process.env.LIVE_TRADING || "false") === "true";

  if (!live) {
    return {
      mode: "simulation",
      action: signal,
      symbol,
      quantity,
      ts: Date.now(),
    };
  }

  const binanceClient = getClient();
  if (!binanceClient) {
    return {
      mode: "live",
      action: "HOLD",
      symbol,
      quantity,
      error: "binance_client_unavailable",
      ts: Date.now(),
    };
  }

  if (signal === "BUY") return safeBuy(binanceClient, symbol, quantity);
  if (signal === "SELL") return safeSell(binanceClient, symbol, quantity);

  return { mode: "live", action: "HOLD", symbol, quantity, ts: Date.now() };
}
