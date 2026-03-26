import test from "node:test";
import assert from "node:assert/strict";
import { BacktestEngine, calculateTradeStats } from "./engine.js";

test("BacktestEngine closes positions via stop loss", () => {
  const candles = [{ price: 100 }, { price: 98 }, { price: 96 }, { price: 90 }];
  let bought = false;
  const strategy = () => {
    if (!bought) {
      bought = true;
      return "BUY";
    }
    return "HOLD";
  };

  const engine = new BacktestEngine(strategy, candles, { stopLossPercent: 0.03, feeRate: 0, slippageRate: 0 });
  const result = engine.run();
  const finalTrade = result.trades[result.trades.length - 1];

  assert.equal(finalTrade.type, "SELL");
  assert.equal(finalTrade.reason, "stop_loss");
});

test("BacktestEngine closes positions via take profit", () => {
  const candles = [{ price: 100 }, { price: 102 }, { price: 104 }, { price: 106 }];
  let bought = false;
  const strategy = () => {
    if (!bought) {
      bought = true;
      return "BUY";
    }
    return "HOLD";
  };

  const engine = new BacktestEngine(strategy, candles, { takeProfitPercent: 0.03, feeRate: 0, slippageRate: 0 });
  const result = engine.run();
  const finalTrade = result.trades[result.trades.length - 1];

  assert.equal(finalTrade.type, "SELL");
  assert.equal(finalTrade.reason, "take_profit");
});

test("calculateTradeStats reports win-rate and profit factor", () => {
  const trades = [
    { type: "BUY" },
    { type: "SELL", pnl: 200 },
    { type: "BUY" },
    { type: "SELL", pnl: -100 },
    { type: "BUY" },
    { type: "SELL", pnl: 50 },
  ];

  const stats = calculateTradeStats(trades);
  assert.equal(stats.totalTrades, 3);
  assert.equal(stats.winningTrades, 2);
  assert.equal(stats.tradeWinRate, 2 / 3);
  assert.equal(stats.profitFactor, 2.5);
});
