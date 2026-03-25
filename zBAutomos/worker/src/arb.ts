type OB = { bid: number; ask: number; ts: number };

type OrderSide = "BUY" | "SELL";
type ExchangeId = "A" | "B";

const STALE_MS = 30;
const EDGE_BUFFER = 2 * 0.0005;

type CostProfile = {
  fee: number;
  funding: number;
  transfer: number;
};

export async function latencyArb(
  a: OB,
  b: OB,
  costA: CostProfile,
  costB: CostProfile,
): Promise<"A->B" | "B->A" | "NONE"> {
  const now = Date.now();
  if (now - a.ts > STALE_MS || now - b.ts > STALE_MS) {
    return "NONE";
  }

  const edgeAB =
    a.bid * (1 - costA.fee) -
    b.ask * (1 + costB.fee) -
    (costA.funding + costB.funding + costA.transfer + costB.transfer);

  const edgeBA =
    b.bid * (1 - costB.fee) -
    a.ask * (1 + costA.fee) -
    (costA.funding + costB.funding + costA.transfer + costB.transfer);

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
  // implement exchange adapter (REST/WS/FIX)
  return { exchange, side, px, options };
}
