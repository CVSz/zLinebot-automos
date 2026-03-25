import { query } from "../db.js";

export async function follow(userId, masterId) {
  if (Number(userId) === Number(masterId)) {
    throw new Error("cannot_follow_self");
  }

  await query(
    `INSERT INTO followers(user_id, master_id)
     VALUES($1,$2)
     ON CONFLICT (user_id, master_id) DO NOTHING`,
    [userId, masterId],
  );

  return { userId: Number(userId), masterId: Number(masterId), status: "following" };
}

export async function unfollow(userId, masterId) {
  await query("DELETE FROM followers WHERE user_id=$1 AND master_id=$2", [userId, masterId]);
  return { userId: Number(userId), masterId: Number(masterId), status: "unfollowed" };
}
