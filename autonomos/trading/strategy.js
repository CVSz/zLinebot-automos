import { EMA, MACD, RSI } from "technicalindicators";

export function strategy(prices) {
  if (!prices || prices.length < 60) return "HOLD";

  const rsi = RSI.calculate({ period: 14, values: prices }).slice(-1)[0];
  const macd = MACD.calculate({
    values: prices,
    fastPeriod: 12,
    slowPeriod: 26,
    signalPeriod: 9,
    SimpleMAOscillator: false,
    SimpleMASignal: false,
  }).slice(-1)[0];
  const ema = EMA.calculate({ period: 50, values: prices }).slice(-1)[0];
  const last = prices[prices.length - 1];

  if (rsi < 30 && macd?.histogram > 0 && last > ema) return "BUY";
  if (rsi > 70 && macd?.histogram < 0 && last < ema) return "SELL";
  return "HOLD";
}

