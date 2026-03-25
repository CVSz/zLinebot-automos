export function sharpe(returns, riskFreeRate = 0) {
  if (!returns.length) return 0;

  const adjusted = returns.map((value) => value - riskFreeRate);
  const avg = adjusted.reduce((a, b) => a + b, 0) / adjusted.length;
  const variance = adjusted.reduce((acc, current) => acc + (current - avg) ** 2, 0) / adjusted.length;
  const std = Math.sqrt(variance);

  return std === 0 ? 0 : avg / std;
}

export function drawdown(equityCurve) {
  if (!equityCurve.length) return 0;

  let peak = equityCurve[0];
  let maxDD = 0;

  for (const value of equityCurve) {
    if (value > peak) peak = value;
    const dd = peak === 0 ? 0 : (peak - value) / peak;
    if (dd > maxDD) maxDD = dd;
  }

  return maxDD;
}

export function winRate(trades) {
  if (!trades.length) return 0;
  const wins = trades.filter((trade) => trade.pnl > 0).length;
  return wins / trades.length;
}
