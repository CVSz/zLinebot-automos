import { executeTrade } from "../execution/live.js";
import { checkRisk } from "../risk/manager.js";
import { broadcast } from "../ws/server.js";
import { query } from "../db.js";

function strategyFromName(name = "basic") {
  if (name === "momentum") {
    return (market) => {
      const price = Number(market?.price || 0);
      const prev = Number(market?.prevPrice || 0);
      if (!prev) return "HOLD";
      if (price > prev * 1.002) return "BUY";
      if (price < prev * 0.998) return "SELL";
      return "HOLD";
    };
  }

  return () => "HOLD";
}

async function getUser(userId) {
  const found = await query("SELECT id, balance, role FROM users WHERE id=$1", [userId]);
  return found.rows[0] || null;
}

export async function runUser(userId, market = {}) {
  const user = await getUser(userId);
  if (!user) return { ok: false, reason: "user_not_found" };

  const strategy = strategyFromName(String(market.strategy || "basic"));
  const signal = strategy(market);

  if (signal === "HOLD") {
    return { ok: true, signal, skipped: true };
  }

  const previewPnl = Number(market.pnl || 0);
  if (!checkRisk({ pnl: previewPnl })) {
    return { ok: false, signal, reason: "risk_blocked" };
  }

  const execution = await executeTrade(signal, {
    symbol: market.symbol || "BTCUSDT",
    quantity: Number(market.quantity || 0.001),
  });

  broadcast({
    type: "TRADE",
    userId,
    signal,
    execution,
    pnl: previewPnl,
    ts: Date.now(),
  });

  return { ok: true, signal, execution };
}
