import { strategy } from "./strategy.js";
import { BacktestEngine, calculateMetrics } from "../backtest/engine.js";

const STARTING_BALANCE = 1000;
const LOOKBACK_CANDLES = 60;

function priceSeriesToCandles(prices = []) {
  const candles = new Array(prices.length);
  for (let index = 0; index < prices.length; index += 1) {
    candles[index] = { price: Number(prices[index]), time: index, rsi: 50, macd: 0 };
  }
  return candles;
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
  const rollingPrices = [];
  const wrappedStrategy = (_, state) => {
    const index = state.index;
    rollingPrices.push(prices[index]);
    if (rollingPrices.length > LOOKBACK_CANDLES) {
      rollingPrices.shift();
    }
    return strategy(rollingPrices, config);
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
