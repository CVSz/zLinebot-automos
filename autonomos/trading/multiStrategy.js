import { strategy as primaryStrategy } from "./strategy.js";
import { strategy as altStrategy } from "./strategy_alt.js";

export const strategies = [
  { name: "trend", weight: 0.4 },
  { name: "mean", weight: 0.3 },
  { name: "breakout", weight: 0.3 },
];

export function combinedStrategy(prices) {
  const signals = [primaryStrategy(prices), altStrategy(prices)];

  const buy = signals.filter((s) => s === "BUY").length;
  const sell = signals.filter((s) => s === "SELL").length;

  if (buy > sell) return "BUY";
  if (sell > buy) return "SELL";
  return "HOLD";
}
