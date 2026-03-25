import express from "express";
import { backtest, metrics } from "../trading/backtest.js";
import { brain } from "../agents/brain.js";

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

export default router;
