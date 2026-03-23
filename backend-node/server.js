import express from "express";
import stripe from "stripe";
import cors from "cors";

const app = express();
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const stripeClient = stripe(STRIPE_SECRET_KEY);

app.use(cors());
app.use(express.json());

app.post("/api/create-checkout", async (_req, res) => {
  try {
    const session = await stripeClient.checkout.sessions.create({
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
      success_url: "https://yourdomain.com/success",
      cancel_url: "https://yourdomain.com/cancel",
    });

    res.json({ url: session.url });
  } catch (error) {
    console.error("Stripe checkout error:", error);
    res.status(500).json({ error: "Unable to create checkout session" });
  }
});

app.post("/api/chat", async (req, res) => {
  const { message } = req.body || {};
  const prompt = String(message || "").trim();

  if (!prompt) {
    return res.status(400).json({ reply: "กรุณาพิมพ์ข้อความก่อนส่ง" });
  }

  return res.json({
    reply: `DEMO: ได้รับข้อความ \"${prompt}\" แล้ว ระบบพร้อมเชื่อม AI model จริง`,
  });
});

app.listen(3000, () => console.log("Backend listening on port 3000"));
