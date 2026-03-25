import { Pool } from "pg";

const db = new Pool();

export async function listBots() {
  const { rows } = await db.query(
    `SELECT id, name, price, owner_id
       FROM bots
      WHERE active = true
   ORDER BY id DESC`,
  );

  return rows;
}

export async function purchaseBot(userId: number, botId: number) {
  if (!userId || !botId) {
    throw new Error("Invalid purchase payload");
  }

  const client = await db.connect();

  try {
    await client.query("BEGIN");

    const bot = await client.query(
      `SELECT id, price, owner_id
         FROM bots
        WHERE id = $1
          AND active = true
        FOR UPDATE`,
      [botId],
    );

    if (!bot.rowCount) {
      throw new Error("Bot not found");
    }

    await client.query(
      `INSERT INTO user_bots(user_id, bot_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [userId, botId],
    );

    await client.query("COMMIT");

    return { ok: true, bot: bot.rows[0] };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
