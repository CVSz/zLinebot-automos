export function pnl(trades) {
  if (!Array.isArray(trades)) {
    throw new Error("trades must be an array");
  }

  return trades.reduce((acc, trade) => acc + Number(trade.pnl ?? 0), 0);
}

export function pnlByStrategy(trades) {
  if (!Array.isArray(trades)) {
    throw new Error("trades must be an array");
  }

  return trades.reduce((acc, trade) => {
    const key = trade.strategy ?? "unknown";
    acc[key] = (acc[key] ?? 0) + Number(trade.pnl ?? 0);
    return acc;
  }, {});
}
