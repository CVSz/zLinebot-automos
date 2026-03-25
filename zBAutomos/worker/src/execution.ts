export type Side = "BUY" | "SELL";

export type Venue = {
  id: string;
  sendOrder: (side: Side, price: number, qty: number, options: { tif: "IOC" }) => Promise<{ filledQty: number }>;
};

export async function executeAtomicHedge(
  sellVenue: Venue,
  buyVenue: Venue,
  sellPrice: number,
  buyPrice: number,
  qty: number,
): Promise<void> {
  const [sell, buy] = await Promise.all([
    sellVenue.sendOrder("SELL", sellPrice, qty, { tif: "IOC" }),
    buyVenue.sendOrder("BUY", buyPrice, qty, { tif: "IOC" }),
  ]);

  const residual = Math.abs(sell.filledQty - buy.filledQty);
  if (residual > 0) {
    const hedgeSide: Side = sell.filledQty > buy.filledQty ? "BUY" : "SELL";
    const hedgeVenue = sell.filledQty > buy.filledQty ? buyVenue : sellVenue;
    await hedgeVenue.sendOrder(hedgeSide, hedgeSide === "BUY" ? buyPrice : sellPrice, residual, { tif: "IOC" });
  }
}
