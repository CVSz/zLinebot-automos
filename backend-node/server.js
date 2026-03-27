import cors from "cors";
import express from "express";
import stripe from "stripe";

import { config, hasStripeCheckoutConfig } from "./config.js";

const app = express();
const stripeClient = hasStripeCheckoutConfig ? stripe(config.stripeSecretKey) : null;

app.use(
  cors({
    origin: config.allowedOrigins,
  })
);
app.use(express.json({ limit: "1mb" }));

app.get("/health", (_req, res) => {
  res.status(200).json({ ok: true, service: "backend-node", env: config.nodeEnv });
});

app.post("/api/create-checkout", async (_req, res) => {
  if (!stripeClient) {
    return res.status(503).json({ error: "Stripe checkout is not configured" });
  }

  try {
    const session = await stripeClient.checkout.sessions.create({
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [{ price: config.stripePriceId, quantity: 1 }],
      success_url: `${config.appBaseUrl.replace(/\/$/, "")}/success`,
      cancel_url: `${config.appBaseUrl.replace(/\/$/, "")}/cancel`,
    });

    return res.json({ url: session.url });
  } catch (error) {
    console.error("Stripe checkout error:", error);
    return res.status(500).json({ error: "Unable to create checkout session" });
  }
});

app.post("/api/chat", async (req, res) => {
  const { message } = req.body || {};
  const prompt = String(message || "").trim();

  if (!prompt) {
    return res.status(400).json({ reply: "กรุณาพิมพ์ข้อความก่อนส่ง" });
  }

  if (prompt.length > config.chatMaxLength) {
    return res.status(413).json({ reply: `ข้อความยาวเกินไป (สูงสุด ${config.chatMaxLength} ตัวอักษร)` });
  }

  return res.json({
    reply: `DEMO: ได้รับข้อความ \"${prompt}\" แล้ว ระบบพร้อมเชื่อม AI model จริง`,
  });
});

app.listen(config.serverPort, () => {
  console.log(`Backend listening on port ${config.serverPort}`);
});
