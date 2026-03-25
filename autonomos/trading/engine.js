import { createClient, safeBuy, safeSell } from "./binance_safe.js";
import { combinedStrategy } from "./multiStrategy.js";
import { guard } from "./profitGuard.js";
import { riskControl } from "./risk.js";

const client = createClient();

export async function runTradingEngine({ prices, balance, symbol = "BTCUSDT" }) {
  const action = combinedStrategy(prices);
  const price = prices[prices.length - 1];
  const { amount } = riskControl(balance, price);
  const live = String(process.env.LIVE_TRADING || "false") === "true";

  if (!guard(0)) {
    return { mode: "paused", reason: "daily-loss-limit", action: "HOLD", symbol, price };
  }

  if (!live) {
    return { mode: "simulation", action, amount, symbol, price };
  }

  if (action === "BUY") return safeBuy(client, symbol, amount);
  if (action === "SELL") return safeSell(client, symbol, amount);
  return { mode: "live", action: "HOLD", amount: 0, symbol, price };
}

export async function run() {
  return { status: "idle", message: "Provide market data to runTradingEngine" };
}
