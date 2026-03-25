import { createClient, safeBuy, safeSell } from "./binance_safe.js";
import { combinedStrategy } from "./multiStrategy.js";
import { guard } from "./profitGuard.js";
import { riskControl } from "./risk.js";
import { RLAgent } from "./rl_agent.js";
import { propagate } from "../copy/propagate.js";

const client = createClient();
const agent = new RLAgent();

function resolveAction(prices, indicators) {
  const state = agent.getState(indicators);
  const rlAction = agent.chooseAction(state);
  const strategyAction = combinedStrategy(prices);

  if (rlAction === "HOLD") return { action: strategyAction, state, nextState: state };
  return { action: rlAction, state, nextState: state };
}

export async function runTradingEngine({ prices, balance, symbol = "BTCUSDT", indicators = {}, traderId = "bot-master" }) {
  const price = prices[prices.length - 1];
  const { action, state, nextState } = resolveAction(prices, indicators);
  const { amount } = riskControl(balance, price);
  const live = String(process.env.LIVE_TRADING || "false") === "true";

  if (!guard(0)) {
    return { mode: "paused", reason: "daily-loss-limit", action: "HOLD", symbol, price };
  }

  const tradePayload = { action, amount, symbol, price, ts: Date.now() };

  if (!live) {
    agent.update(state, action, Number(indicators.lastProfit || 0), nextState);
    const copied = await propagate(traderId, {
      side: action,
      size: amount,
      symbol,
      price,
      pnl: Number(indicators.lastProfit || 0),
    });
    return { mode: "simulation", ...tradePayload, copied };
  }

  let execution = { mode: "live", action: "HOLD", amount: 0, symbol, price };
  if (action === "BUY") execution = await safeBuy(client, symbol, amount);
  if (action === "SELL") execution = await safeSell(client, symbol, amount);

  const copied = await propagate(traderId, {
      side: action,
      size: amount,
      symbol,
      price,
      pnl: Number(indicators.lastProfit || 0),
    });
  return { ...execution, copied };
}

export async function run() {
  return { status: "idle", message: "Provide market data to runTradingEngine" };
}
