export type OrderBook = { bid: number; ask: number };

export type ExchangeAdapter = {
  name: string;
  getOrderBook: (symbol: string) => Promise<OrderBook>;
  limitOrder: (symbol: string, side: "buy" | "sell", size: number, price: number) => Promise<unknown>;
};

export async function bestExecution(
  exchanges: ExchangeAdapter[],
  symbol: string,
  side: "buy" | "sell",
  size: number,
  expectedPrice: number,
  maxSlippageBps = 20,
) {
  let best: { exchange: ExchangeAdapter; price: number } | null = null;

  for (const exchange of exchanges) {
    const orderBook = await exchange.getOrderBook(symbol);
    const price = side === "buy" ? orderBook.ask : orderBook.bid;

    if (!best) {
      best = { exchange, price };
      continue;
    }

    if ((side === "buy" && price < best.price) || (side === "sell" && price > best.price)) {
      best = { exchange, price };
    }
  }

  if (!best) {
    throw new Error("No liquidity available");
  }

  const slippage = Math.abs(best.price - expectedPrice) / expectedPrice;
  if (slippage > maxSlippageBps / 10_000) {
    throw new Error(`Slippage too high: ${(slippage * 100).toFixed(3)}%`);
  }

  return best.exchange.limitOrder(symbol, side, size, best.price);
}
