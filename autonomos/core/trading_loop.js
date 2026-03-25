import { BacktestEngine } from "../backtest/engine.js";
import { strategy as advancedStrategy } from "../strategy/advanced.js";
import { optimize } from "../ai/tuner.js";
import { combine } from "../portfolio/manager.js";
import { executeTrade } from "../execution/live.js";

function buildParameterizedStrategy(params = {}) {
  const { rsiLow = 30, rsiHigh = 70 } = params;

  return (candle, state = {}) => {
    if (state.position > 0 && candle.price < state.entry * 0.97) return "SELL";
    if (candle.rsi < rsiLow && candle.macd > 0) return "BUY";
    if (candle.rsi > rsiHigh && candle.macd < 0) return "SELL";
    return "HOLD";
  };
}

export async function tradingLoop(marketData = [], options = {}) {
  const validationTarget = Number(options.validationTarget || 11_000);
  const liveWindow = Number(options.liveWindow || 50);
  const symbol = options.symbol || "BTCUSDT";
  const quantity = Number(options.quantity || process.env.DEFAULT_ORDER_SIZE || 0.001);

  const bestParams = optimize(marketData);
  const tunedStrategy = buildParameterizedStrategy(bestParams);
  const backtest = new BacktestEngine(tunedStrategy, marketData, {
    startingBalance: Number(options.startingBalance || 10_000),
    feeRate: Number(options.feeRate || 0.001),
  });
  const result = backtest.run();

  if (result.endingBalance < validationTarget) {
    return {
      approved: false,
      reason: "validation_target_not_met",
      target: validationTarget,
      backtest: result,
      bestParams,
      executions: [],
    };
  }

  const strategies = [advancedStrategy, tunedStrategy];
  const window = marketData.slice(-liveWindow);
  const executions = [];

  for (const candle of window) {
    const signal = combine(strategies, candle, {
      entry: result.trades.findLast?.((trade) => trade.type === "BUY")?.price || 0,
      position: 1,
    });

    if (signal === "HOLD") continue;
    const execution = await executeTrade(signal, { symbol, quantity });
    executions.push({ candleTime: candle?.time || Date.now(), signal, execution });
  }

  return {
    approved: true,
    backtest: result,
    bestParams,
    executions,
  };
}
