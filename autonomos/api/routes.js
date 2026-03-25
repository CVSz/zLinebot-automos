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
import { follow, unfollow } from "../copy/follow.js";
import { getLeaderboard } from "../copy/leaderboard.js";
import { createCheckout, webhook } from "../billing/stripe.js";
import { getAdminUsers, getAdminTrades, getAdminSubscriptions, getAdminLogs } from "../admin/api.js";
import { getCachedPrice, setCachedPrice } from "../cache/marketCache.js";

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.user?.role !== "admin") return res.status(403).json({ error: "admin_only" });
  return next();
}

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

router.get("/market/cache/:symbol", auth, async (req, res, next) => {
  try {
    const symbol = String(req.params.symbol || "BTCUSDT").toUpperCase();
    const cached = await getCachedPrice(symbol);
    return res.json({ symbol, cached });
  } catch (error) {
    return next(error);
  }
});

router.post("/market/cache/:symbol", auth, async (req, res, next) => {
  try {
    const symbol = String(req.params.symbol || "BTCUSDT").toUpperCase();
    const payload = req.body?.data || {};
    await setCachedPrice(symbol, payload);
    return res.status(201).json({ symbol, cached: true });
  } catch (error) {
    return next(error);
  }
});

router.post("/kyc", auth, (req, res) => {
  const { user, docs } = req.body || {};
  const result = submitKYC(user || String(req.user.id), docs || []);
  const audit = logAction(user || String(req.user.id), "kyc_submitted", {
    docsCount: Array.isArray(docs) ? docs.length : 0,
  });

  return res.json({ ...result, audit });
});


router.post("/copy/follow", auth, async (req, res, next) => {
  try {
    const masterId = Number(req.body?.masterId);
    if (!masterId) return res.status(400).json({ error: "master_id_required" });
    const result = await follow(req.user.id, masterId);
    return res.status(201).json(result);
  } catch (error) {
    return next(error);
  }
});

router.post("/copy/unfollow", auth, async (req, res, next) => {
  try {
    const masterId = Number(req.body?.masterId);
    if (!masterId) return res.status(400).json({ error: "master_id_required" });
    const result = await unfollow(req.user.id, masterId);
    return res.json(result);
  } catch (error) {
    return next(error);
  }
});

router.get("/copy/leaderboard", auth, async (req, res, next) => {
  try {
    const limit = Number(req.query?.limit || 50);
    const rows = await getLeaderboard(Math.min(Math.max(limit, 1), 200));
    return res.json(rows);
  } catch (error) {
    return next(error);
  }
});

router.post("/billing/checkout", auth, async (req, res, next) => {
  try {
    const checkout = await createCheckout(req.user.id);
    return res.json({ id: checkout.id, url: checkout.url });
  } catch (error) {
    return next(error);
  }
});

router.post("/billing/webhook", express.raw({ type: "application/json" }), webhook);

router.get("/admin/users", auth, requireAdmin, async (req, res, next) => {
  try {
    const users = await getAdminUsers();
    return res.json(users);
  } catch (error) {
    return next(error);
  }
});

router.get("/admin/subscriptions", auth, requireAdmin, async (req, res, next) => {
  try {
    const subscriptions = await getAdminSubscriptions();
    return res.json(subscriptions);
  } catch (error) {
    return next(error);
  }
});

router.get("/admin/trades", auth, requireAdmin, async (req, res, next) => {
  try {
    const trades = await getAdminTrades();
    return res.json(trades);
  } catch (error) {
    return next(error);
  }
});

router.get("/admin/logs", auth, requireAdmin, async (req, res, next) => {
  try {
    const logs = await getAdminLogs();
    return res.json(logs);
  } catch (error) {
    return next(error);
  }
});

export default router;
