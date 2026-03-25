type Trade = {
  side: "buy" | "sell";
  size: number;
};

type DbClient = {
  query: (sql: string, params: unknown[]) => Promise<{ rows: { user_id: string }[] }>;
};

type Executor = (userId: string, side: Trade["side"], size: number) => Promise<unknown>;

export async function propagate(
  db: DbClient,
  executeTrade: Executor,
  masterId: string,
  trade: Trade,
): Promise<void> {
  const followers = await db.query("SELECT user_id FROM followers WHERE master_id=$1", [masterId]);

  await Promise.all(followers.rows.map((follower) => executeTrade(follower.user_id, trade.side, trade.size)));
}
