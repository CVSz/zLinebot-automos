type SimulationResult = { pnl: number; trades: number; maxDrawdown: number };

type StrategyConfig = {
  rsi: number;
  tp: number;
};

export type OptimizerResult = {
  score: number;
  config: StrategyConfig | null;
};

function scoreResult(result: SimulationResult) {
  // Penalize drawdowns while favoring net PnL and minimum trade count.
  return result.pnl - result.maxDrawdown * 0.5 + Math.min(result.trades, 100) * 0.01;
}

export function optimize(
  data: number[],
  simulate: (candles: number[], config: StrategyConfig) => SimulationResult,
): OptimizerResult {
  let best: OptimizerResult = { score: -Infinity, config: null };

  for (let rsi = 10; rsi <= 30; rsi += 5) {
    for (let tp = 1.01; tp <= 1.05; tp += 0.01) {
      const result = simulate(data, { rsi, tp: Number(tp.toFixed(2)) });
      const score = scoreResult(result);

      if (score > best.score) {
        best = { score, config: { rsi, tp: Number(tp.toFixed(2)) } };
      }
    }
  }

  return best;
}
