import { query } from "../db.js";

export async function getAdminUsers() {
  const users = await query("SELECT id, email, role, plan, balance, created_at FROM users ORDER BY id DESC LIMIT 500");
  return users.rows;
}

export async function getAdminTrades() {
  const trades = await query("SELECT * FROM trades ORDER BY created_at DESC LIMIT 2000");
  return trades.rows;
}

export async function getAdminSubscriptions() {
  const subscriptions = await query(
    "SELECT user_id, stripe_customer_id, stripe_subscription_id, status, current_period_end FROM subscriptions ORDER BY current_period_end DESC NULLS LAST LIMIT 500",
  );
  return subscriptions.rows;
}

export async function getAdminLogs() {
  const logs = await query("SELECT id, actor_user_id, action, payload, created_at FROM admin_logs ORDER BY created_at DESC LIMIT 1000");
  return logs.rows;
}
