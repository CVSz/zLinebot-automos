import { strategy } from "./strategy.js";
import { BacktestEngine, calculateMetrics } from "../backtest/engine.js";

const STARTING_BALANCE = 1000;
const LOOKBACK_CANDLES = 60;

function priceSeriesToCandles(prices = []) {
  return prices.map((price, index) => ({ price: Number(price), time: index, rsi: 50, macd: 0 }));
}

export function backtest(prices, config = {}) {
  if (!Array.isArray(prices) || prices.length <= LOOKBACK_CANDLES) {
    return {
      start: STARTING_BALANCE,
      end: STARTING_BALANCE,
      profit: 0,
      trades: [],
      metrics: calculateMetrics([], []),
    };
  }

  const candles = priceSeriesToCandles(prices);
  const wrappedStrategy = (_, state) => {
    const start = Math.max(0, state.index - LOOKBACK_CANDLES + 1);
    const window = prices.slice(start, state.index + 1);
    return strategy(window, config);
  };

  const engine = new BacktestEngine(wrappedStrategy, candles, {
    startingBalance: STARTING_BALANCE,
    feeRate: Number(config.feeRate || 0),
    slippageRate: Number(config.slippageRate || 0),
  });

  const result = engine.run();

  return {
    start: STARTING_BALANCE,
    end: result.endingBalance,
    profit: result.profit,
    trades: result.trades,
    metrics: result.metrics,
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
