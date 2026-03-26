import Stripe from "stripe";
import { query } from "../db.js";

const stripeSecret = process.env.STRIPE_SECRET || "";
const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || "";

const stripe = new Stripe(stripeSecret, {
  apiVersion: "2025-02-24.acacia",
});

export async function createCheckout(userId) {
  if (!stripeSecret) {
    throw new Error("stripe_not_configured");
  }

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
    if (!webhookSecret) {
      return res.status(503).json({ error: "webhook_secret_not_configured" });
    }

    const signature = req.headers["stripe-signature"];
    if (!signature) {
      return res.status(400).json({ error: "missing_stripe_signature" });
    }

    const event = stripe.webhooks.constructEvent(req.body, signature, webhookSecret);

    if (event.type === "checkout.session.completed") {
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
    if (error?.type === "StripeSignatureVerificationError") {
      return res.status(400).json({ error: "invalid_stripe_signature" });
    }

    return next(error);
  }
}
