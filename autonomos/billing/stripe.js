import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET || "", {
  apiVersion: "2025-02-24.acacia",
});

export async function createCheckout(userId) {
  return stripe.checkout.sessions.create({
    payment_method_types: ["card"],
    metadata: { userId },
    line_items: [
      {
        price_data: {
          currency: "usd",
          product_data: { name: "zLineBot Pro" },
          unit_amount: 2000,
          recurring: { interval: "month" },
        },
        quantity: 1,
      },
    ],
    mode: "subscription",
    success_url: process.env.STRIPE_SUCCESS_URL || "https://yourdomain/success",
    cancel_url: process.env.STRIPE_CANCEL_URL || "https://yourdomain/cancel",
  });
}
