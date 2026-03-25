import express from "express";
import { backtest, metrics } from "../trading/backtest.js";
import { brain } from "../agents/brain.js";
import { submitKYC, logAction } from "../kyc/service.js";
import { tradingLoop } from "../core/trading_loop.js";
import { optimize } from "../ai/tuner.js";
import { auth } from "../middleware/auth.js";
import { register } from "../auth/register.js";
import { login } from "../auth/login.js";
import { enqueueUserRun } from "../queue/tradingQueue.js";
import { getRiskState } from "../risk/manager.js";

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

router.post("/auth/register", register);
router.post("/auth/login", login);

router.get("/portfolio", auth, (req, res) => {
  return res.json({
    userId: req.user.id,
    value: 12_500,
    pnl: 2_300,
    sharpe: 1.8,
    updatedAt: new Date().toISOString(),
  });
});

router.get("/backtest", auth, (req, res) => {
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

router.get("/optimize", auth, async (req, res, next) => {
  try {
    const data = generateFakePrices();
    const best = await brain(data);
    return res.json(best);
  } catch (error) {
    return next(error);
  }
});

router.get("/pipeline/tune", auth, (req, res) => {
  const candles = generateMarketData();
  const best = optimize(candles);
  return res.json(best);
});

router.post("/pipeline/run", auth, async (req, res, next) => {
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

router.post("/trading/queue", auth, async (req, res, next) => {
  try {
    const userId = Number(req.body?.userId || req.user.id);
    const job = await enqueueUserRun(userId, req.body?.market || {});
    return res.status(202).json({ queued: true, jobId: job.id, userId });
  } catch (error) {
    return next(error);
  }
});

router.get("/risk", auth, (req, res) => res.json(getRiskState()));

router.post("/kyc", auth, (req, res) => {
  const { user, docs } = req.body || {};
  const result = submitKYC(user || String(req.user.id), docs || []);
  const audit = logAction(user || String(req.user.id), "kyc_submitted", {
    docsCount: Array.isArray(docs) ? docs.length : 0,
  });

  return res.json({ ...result, audit });
});

export default router;
