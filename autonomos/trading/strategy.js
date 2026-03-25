import { EMA, MACD, RSI } from "technicalindicators";

export function strategy(prices, config = {}) {
  const rsiPeriod = config.rsi || 14;
  const emaPeriod = config.ema || 50;
  const rsiBuy = config.rsiBuy || 30;
  const rsiSell = config.rsiSell || 70;

  if (!prices || prices.length < Math.max(60, emaPeriod + 10)) return "HOLD";

  const rsi = RSI.calculate({ period: rsiPeriod, values: prices }).slice(-1)[0];
  const macd = MACD.calculate({
    values: prices,
    fastPeriod: config.macdFast || 12,
    slowPeriod: config.macdSlow || 26,
    signalPeriod: config.macdSignal || 9,
    SimpleMAOscillator: false,
    SimpleMASignal: false,
  }).slice(-1)[0];
  const ema = EMA.calculate({ period: emaPeriod, values: prices }).slice(-1)[0];
  const last = prices[prices.length - 1];

  if (rsi < rsiBuy && macd?.histogram > 0 && last > ema) return "BUY";
  if (rsi > rsiSell && macd?.histogram < 0 && last < ema) return "SELL";
  return "HOLD";
}
