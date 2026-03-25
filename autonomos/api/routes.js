import express from "express";
import { backtest, metrics } from "../trading/backtest.js";
import { brain } from "../agents/brain.js";
import { submitKYC, logAction } from "../kyc/service.js";

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
    metrics: metrics(report.trades),
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

router.post("/kyc", (req, res) => {
  const { user, docs } = req.body || {};
  const result = submitKYC(user || "unknown", docs || []);
  const audit = logAction(user || "unknown", "kyc_submitted", {
    docsCount: Array.isArray(docs) ? docs.length : 0,
  });

  return res.json({ ...result, audit });
});

export default router;
