import Stripe from "stripe";
import { query } from "../db.js";

const stripe = new Stripe(process.env.STRIPE_SECRET || "", {
  apiVersion: "2025-02-24.acacia",
});

export async function createCheckout(userId) {
  return stripe.checkout.sessions.create({
    payment_method_types: ["card"],
    client_reference_id: String(userId),
    metadata: { userId: String(userId) },
    line_items: [
      {
        price: process.env.STRIPE_PRICE_ID || "price_123",
        quantity: 1,
      },
    ],
    mode: "subscription",
    success_url: process.env.STRIPE_SUCCESS_URL || "https://yourdomain/success",
    cancel_url: process.env.STRIPE_CANCEL_URL || "https://yourdomain/cancel",
  });
}

export async function webhook(req, res, next) {
  try {
    const event = req.body;

    if (event?.type === "checkout.session.completed") {
      const session = event.data.object;
      const userId = Number(session.client_reference_id || session.metadata?.userId);

      if (userId) {
        await query("UPDATE users SET plan='pro' WHERE id=$1", [userId]);
        await query(
          `INSERT INTO subscriptions(user_id, stripe_customer_id, stripe_subscription_id, status)
           VALUES($1,$2,$3,'active')
           ON CONFLICT (user_id) DO UPDATE SET
             stripe_customer_id=EXCLUDED.stripe_customer_id,
             stripe_subscription_id=EXCLUDED.stripe_subscription_id,
             status='active',
             updated_at=NOW()`,
          [userId, session.customer || null, session.subscription || null],
        );
      }
    }

    return res.sendStatus(200);
  } catch (error) {
    return next(error);
  }
}
