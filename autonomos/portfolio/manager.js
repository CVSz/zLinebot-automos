export function combine(strategies = [], candle, state = {}) {
  const signals = strategies
    .map((strategy) => {
      try {
        return strategy(candle, state);
      } catch {
        return "HOLD";
      }
    })
    .filter(Boolean);

  const buy = signals.filter((signal) => signal === "BUY").length;
  const sell = signals.filter((signal) => signal === "SELL").length;

  if (buy > sell) return "BUY";
  if (sell > buy) return "SELL";
  return "HOLD";
}
