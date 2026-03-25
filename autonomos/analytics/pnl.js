export function pnl(trades) {
  return trades.reduce((acc, trade) => acc + Number(trade.pnl || 0), 0);
}
