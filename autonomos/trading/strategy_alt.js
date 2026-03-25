import { EMA } from "technicalindicators";

export function strategy(prices) {
  if (!prices || prices.length < 30) return "HOLD";

  const emaFast = EMA.calculate({ period: 9, values: prices }).slice(-1)[0];
  const emaSlow = EMA.calculate({ period: 21, values: prices }).slice(-1)[0];

  if (emaFast > emaSlow) return "BUY";
  if (emaFast < emaSlow) return "SELL";
  return "HOLD";
}
