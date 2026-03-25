import { Pool, PoolClient } from "pg";

const db = new Pool();

export type ReferralResult = {
  created: boolean;
  creditsAwarded: number;
};

async function awardReferralCredit(client: PoolClient, referrerId: number) {
  await client.query(
    `UPDATE users
       SET credits = credits + 10
     WHERE id = $1`,
    [referrerId],
  );
}

export async function createReferral(
  referrerId: number,
  refereeId: number,
): Promise<ReferralResult> {
  if (!referrerId || !refereeId || referrerId === refereeId) {
    throw new Error("Invalid referral payload");
  }

  const client = await db.connect();

  try {
    await client.query("BEGIN");

    const inserted = await client.query(
      `INSERT INTO referrals(referrer_id, referee_id)
       VALUES ($1, $2)
       ON CONFLICT DO NOTHING
       RETURNING id`,
      [referrerId, refereeId],
    );

    if (!inserted.rowCount) {
      await client.query("COMMIT");
      return { created: false, creditsAwarded: 0 };
    }

    await awardReferralCredit(client, referrerId);
    await client.query("COMMIT");

    return { created: true, creditsAwarded: 10 };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
