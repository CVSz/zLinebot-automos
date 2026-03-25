import { backtest } from "./backtest.js";

export async function optimize(prices) {
  let best = { profit: -Infinity, config: null, report: null };

  for (let rsi = 10; rsi <= 20; rsi += 2) {
    for (let ema = 20; ema <= 100; ema += 10) {
      const config = { rsi, ema };
      const result = backtest(prices, config);

      if (result.profit > best.profit) {
        best = { profit: result.profit, config, report: result };
      }
    }
  }

  return best;
}
