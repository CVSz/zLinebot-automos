export function makeMarket(orderbook, { minSpread = 5, tickSize = 1, position = 0, maxPosition = 1 } = {}) {
  const bestBid = Number(orderbook?.bids?.[0]?.[0] ?? 0);
  const bestAsk = Number(orderbook?.asks?.[0]?.[0] ?? 0);

  if (!bestBid || !bestAsk || bestAsk <= bestBid) {
    return null;
  }

  const spread = bestAsk - bestBid;
  if (spread < minSpread) return null;

  return {
    buy: position >= maxPosition ? null : bestBid + tickSize,
    sell: position <= -maxPosition ? null : bestAsk - tickSize,
    spread,
  };
}
