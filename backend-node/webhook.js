import express from "express";
import stripe from "stripe";

import { config, hasStripeWebhookConfig } from "./config.js";

const app = express();
app.use(express.raw({ type: "application/json", limit: "1mb" }));

const stripeClient = hasStripeWebhookConfig ? stripe(config.stripeSecretKey) : null;

app.get("/health", (_req, res) => {
  res.status(200).json({ ok: true, service: "webhook", env: config.nodeEnv });
});

app.post("/webhook", async (req, res) => {
  if (!stripeClient) {
    return res.status(503).json({ error: "Stripe webhook is not configured" });
  }

  const sig = req.headers["stripe-signature"];
  let event;

  try {
    event = stripeClient.webhooks.constructEvent(req.body, sig, config.stripeWebhookSecret);
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    console.log("Customer paid:", session.customer_email || session.customer);
    // TODO: update DB user role to "paid"
  }

  return res.json({ received: true });
});

app.listen(config.webhookPort, () => {
  console.log(`Webhook listening on ${config.webhookPort}`);
});
