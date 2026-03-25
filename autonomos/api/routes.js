import express from "express";
import { backtest, metrics } from "../trading/backtest.js";
import { brain } from "../agents/brain.js";
import { submitKYC, logAction } from "../kyc/service.js";
import { tradingLoop } from "../core/trading_loop.js";
import { optimize } from "../ai/tuner.js";

const router = express.Router();

function generateFakePrices(size = 240, start = 100) {
  const values = [];
  let price = start;

  for (let i = 0; i < size; i++) {
    const drift = (Math.random() - 0.48) * 2;
    price = Math.max(1, price + drift);
    values.push(Number(price.toFixed(2)));
  }

  return values;
}

function generateMarketData(size = 300, start = 100) {
  const candles = [];
  let price = start;

  for (let i = 0; i < size; i++) {
    const drift = (Math.random() - 0.49) * 2;
    price = Math.max(1, price + drift);

    candles.push({
      time: Date.now() - (size - i) * 60_000,
      price: Number(price.toFixed(2)),
      rsi: Math.max(1, Math.min(99, 50 + drift * 20 + (Math.random() - 0.5) * 8)),
      macd: Number((drift + (Math.random() - 0.5)).toFixed(4)),
    });
  }

  return candles;
}

router.get("/portfolio", (req, res) => {
  return res.json({
    value: 12_500,
    pnl: 2_300,
    sharpe: 1.8,
    updatedAt: new Date().toISOString(),
  });
});

router.get("/backtest", (req, res) => {
  const data = generateFakePrices();
  const report = backtest(data);

  return res.json({
    ...report,
    metrics: {
      ...report.metrics,
      ...metrics(report.trades),
    },
  });
});

router.get("/optimize", async (req, res, next) => {
  try {
    const data = generateFakePrices();
    const best = await brain(data);
    return res.json(best);
  } catch (error) {
    return next(error);
  }
});

router.get("/pipeline/tune", (req, res) => {
  const candles = generateMarketData();
  const best = optimize(candles);
  return res.json(best);
});

router.post("/pipeline/run", async (req, res, next) => {
  try {
    const candles = Array.isArray(req.body?.marketData) && req.body.marketData.length
      ? req.body.marketData
      : generateMarketData();

    const result = await tradingLoop(candles, {
      validationTarget: req.body?.validationTarget,
      symbol: req.body?.symbol,
      quantity: req.body?.quantity,
      liveWindow: req.body?.liveWindow,
      startingBalance: req.body?.startingBalance,
      feeRate: req.body?.feeRate,
    });

    return res.json(result);
  } catch (error) {
    return next(error);
  }
});

router.post("/kyc", (req, res) => {
  const { user, docs } = req.body || {};
  const result = submitKYC(user || "unknown", docs || []);
  const audit = logAction(user || "unknown", "kyc_submitted", {
    docsCount: Array.isArray(docs) ? docs.length : 0,
  });

  return res.json({ ...result, audit });
});

export default router;
