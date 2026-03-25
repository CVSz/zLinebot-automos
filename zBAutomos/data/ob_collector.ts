export type BookLevel = { price: number; size: number };
export type BookSnapshot = {
  ts: number;
  bids: BookLevel[];
  asks: BookLevel[];
};

export function toImbalance(snapshot: BookSnapshot) {
  const bidVol = snapshot.bids.reduce((sum, b) => sum + b.size, 0);
  const askVol = snapshot.asks.reduce((sum, a) => sum + a.size, 0);
  const denom = bidVol + askVol;
  return denom === 0 ? 0 : (bidVol - askVol) / denom;
}
