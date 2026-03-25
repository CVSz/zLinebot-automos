import { query } from "../db.js";

export async function getLeaderboard(limit = 50) {
  const result = await query(
    `SELECT user_id, SUM(pnl) AS profit
     FROM trades
     GROUP BY user_id
     ORDER BY profit DESC
     LIMIT $1`,
    [limit],
  );

  return result.rows;
}
