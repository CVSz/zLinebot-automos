export function strategy(candle, state = {}) {
  const rsi = Number(candle?.rsi);
  const macd = Number(candle?.macd);
  const price = Number(candle?.price);

  if (!Number.isFinite(price) || price <= 0) return "HOLD";

  const entry = Number(state.entry || 0);
  const hasPosition = Number(state.position || 0) > 0;

  if (hasPosition && entry > 0) {
    if (price <= entry * 0.97) return "SELL";
    if (price >= entry * 1.05) return "SELL";
  }

  if (Number.isFinite(rsi) && Number.isFinite(macd)) {
    if (rsi < 30 && macd > 0) return "BUY";
    if (rsi > 70 && macd < 0) return "SELL";
  }

  return "HOLD";
}
