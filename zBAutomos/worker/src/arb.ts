type OB = { bid: number; ask: number; ts: number };

type OrderSide = "BUY" | "SELL";
type ExchangeId = "A" | "B";

const STALE_MS = 30;
const EDGE_BUFFER = 2 * 0.0005;

export async function latencyArb(a: OB, b: OB, feeA: number, feeB: number): Promise<"A->B" | "B->A" | "NONE"> {
  const now = Date.now();
  if (now - a.ts > STALE_MS || now - b.ts > STALE_MS) {
    return "NONE";
  }

  const edgeAB = a.bid * (1 - feeA) - b.ask * (1 + feeB);
  const edgeBA = b.bid * (1 - feeB) - a.ask * (1 + feeA);

  if (edgeAB > EDGE_BUFFER) {
    await Promise.all([execSell("A", a.bid), execBuy("B", b.ask)]);
    return "A->B";
  }

  if (edgeBA > EDGE_BUFFER) {
    await Promise.all([execSell("B", b.bid), execBuy("A", a.ask)]);
    return "B->A";
  }

  return "NONE";
}

async function execBuy(exchange: ExchangeId, px: number) {
  return placeOrder(exchange, "BUY", px, { tif: "IOC" });
}

async function execSell(exchange: ExchangeId, px: number) {
  return placeOrder(exchange, "SELL", px, { tif: "IOC" });
}

async function placeOrder(exchange: ExchangeId, side: OrderSide, px: number, options: { tif: "IOC" }) {
  return { exchange, side, px, options };
}
