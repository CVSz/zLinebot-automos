import { marketBuy, marketSell } from "./binance.js";
import { riskControl } from "./risk.js";
import { strategy } from "./strategy.js";

export async function runTradingEngine({ prices, balance, symbol = "BTCUSDT" }) {
  const action = strategy(prices);
  const price = prices[prices.length - 1];
  const { amount } = riskControl(balance, price);
  const live = String(process.env.LIVE_TRADING || "false") === "true";

  if (!live) {
    return { mode: "simulation", action, amount, symbol, price };
  }

  if (action === "BUY") return marketBuy(symbol, amount);
  if (action === "SELL") return marketSell(symbol, amount);
  return { mode: "live", action: "HOLD", amount: 0, symbol, price };
}

