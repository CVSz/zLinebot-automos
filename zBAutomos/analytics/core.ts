export function sharpe(returns: number[]) {
  const avg = returns.reduce((a, b) => a + b, 0) / returns.length;
  const variance = returns
    .map((r) => (r - avg) ** 2)
    .reduce((a, b) => a + b, 0) / returns.length;
  const std = Math.sqrt(variance);
  return avg / std;
}

export function drawdown(equity: number[]) {
  let peak = equity[0];
  let maxDD = 0;

  for (const value of equity) {
    if (value > peak) peak = value;
    const dd = (peak - value) / peak;
    if (dd > maxDD) maxDD = dd;
  }

  return maxDD;
}

export function var95(returns: number[]) {
  const sorted = [...returns].sort((a, b) => a - b);
  return sorted[Math.floor(returns.length * 0.05)];
}
