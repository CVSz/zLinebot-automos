type OrderBook = { bid: number; ask: number };

export function makeMarket(ob: OrderBook, position: number, maxInventory: number) {
  const mid = (ob.bid + ob.ask) / 2;
  const spread = ob.ask - ob.bid;

  const quote = {
    bid: mid - spread * 0.25,
    ask: mid + spread * 0.25,
    canBid: true,
    canAsk: true,
  };

  if (position > maxInventory) {
    quote.canBid = false;
  }

  if (position < -maxInventory) {
    quote.canAsk = false;
  }

  return quote;
}
