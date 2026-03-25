type Side = "buy" | "sell";

type Order = {
  side: Side;
  size: number;
};

type Exchange = {
  orderbook: () => Promise<{ ask: number; bid: number }>;
  limit: (side: Side, size: number, price: number) => Promise<unknown>;
};

export async function execute(order: Order, exchanges: Exchange[]): Promise<unknown> {
  let best: { ex: Exchange; price: number } | null = null;

  for (const ex of exchanges) {
    const ob = await ex.orderbook();
    const price = order.side === "buy" ? ob.ask : ob.bid;

    if (!best || (order.side === "buy" ? price < best.price : price > best.price)) {
      best = { ex, price };
    }
  }

  if (!best) {
    throw new Error("No liquidity");
  }

  return best.ex.limit(order.side, order.size, best.price);
}
