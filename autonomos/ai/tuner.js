import { BacktestEngine } from "../backtest/engine.js";

export function optimize(data = []) {
  let best = { endingBalance: -Infinity, rsiLow: 30, rsiHigh: 70 };

  for (let rsiLow = 20; rsiLow <= 40; rsiLow += 5) {
    for (let rsiHigh = 60; rsiHigh <= 80; rsiHigh += 5) {
      if (rsiLow >= rsiHigh) continue;

      const candidateStrategy = (candle, state) => {
        if (state.position > 0 && candle.price < state.entry * 0.97) return "SELL";
        if (candle.rsi < rsiLow) return "BUY";
        if (candle.rsi > rsiHigh) return "SELL";
        return "HOLD";
      };

      const engine = new BacktestEngine(candidateStrategy, data);
      const result = engine.run();

      if (result.endingBalance > best.endingBalance) {
        best = {
          endingBalance: result.endingBalance,
          profit: result.profit,
          rsiLow,
          rsiHigh,
          sharpe: result.metrics.sharpe,
          maxDrawdown: result.metrics.maxDrawdown,
          trades: result.trades.length,
        };
      }
    }
  }

  return best;
}
