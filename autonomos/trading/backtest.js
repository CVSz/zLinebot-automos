import { strategy } from "./strategy.js";

const STARTING_BALANCE = 1000;
const LOOKBACK_CANDLES = 60;

export function backtest(prices, config = {}) {
  if (!Array.isArray(prices) || prices.length <= LOOKBACK_CANDLES) {
    return {
      start: STARTING_BALANCE,
      end: STARTING_BALANCE,
      profit: 0,
      trades: [],
    };
  }

  let balance = STARTING_BALANCE;
  let position = 0;
  const trades = [];

  for (let i = LOOKBACK_CANDLES; i < prices.length; i++) {
    const slice = prices.slice(i - LOOKBACK_CANDLES, i);
    const price = prices[i];
    const signal = strategy(slice, config);

    if (signal === "BUY" && balance > 0) {
      position = balance / price;
      trades.push({ type: "BUY", price, index: i });
      balance = 0;
    }

    if (signal === "SELL" && position > 0) {
      balance = position * price;
      trades.push({ type: "SELL", price, index: i });
      position = 0;
    }
  }

  const finalValue = balance + position * prices[prices.length - 1];

  return {
    start: STARTING_BALANCE,
    end: finalValue,
    profit: finalValue - STARTING_BALANCE,
    trades,
  };
}

export function metrics(trades = []) {
  let wins = 0;
  let closedTrades = 0;

  for (let i = 1; i < trades.length; i += 2) {
    const entry = trades[i - 1];
    const exit = trades[i];

    if (!entry || !exit || entry.type !== "BUY" || exit.type !== "SELL") continue;

    closedTrades += 1;
    if (exit.price > entry.price) wins += 1;
  }

  return {
    winRate: closedTrades ? wins / closedTrades : 0,
    wins,
    closedTrades,
  };
}
