import { query } from "../db.js";
import { executeTrade } from "../execution/live.js";

export async function propagate(masterId, trade) {
  const followers = await query(
    "SELECT user_id FROM followers WHERE master_id=$1",
    [masterId],
  );

  const copied = [];
  for (const follower of followers.rows) {
    const userId = Number(follower.user_id);
    const execution = await executeTrade(String(trade.side || "HOLD").toUpperCase(), {
      symbol: trade.symbol || "BTCUSDT",
      quantity: Number(trade.size || trade.quantity || 0.001),
    });

    await query(
      `INSERT INTO trades(user_id, symbol, side, quantity, price, pnl)
       VALUES($1,$2,$3,$4,$5,$6)`,
      [
        userId,
        trade.symbol || "BTCUSDT",
        String(trade.side || "HOLD").toUpperCase(),
        Number(trade.size || trade.quantity || 0.001),
        Number(trade.price || execution?.price || 0),
        Number(trade.pnl || 0),
      ],
    );

    copied.push({ userId, execution });
  }

  return copied;
}
