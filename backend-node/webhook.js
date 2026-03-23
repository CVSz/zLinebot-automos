import express from "express";
import stripe from "stripe";

const app = express();
app.use(express.raw({ type: "application/json" }));

const stripeClient = stripe(process.env.STRIPE_SECRET_KEY);

app.post("/webhook", async (req, res) => {
  const sig = req.headers["stripe-signature"];
  let event;

  try {
    event = stripeClient.webhooks.constructEvent(
      req.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    console.log("Customer paid:", session.customer_email);
    // TODO: update DB user role to "paid"
  }

  res.json({ received: true });
});

app.listen(3001, () => console.log("Webhook listening on 3001"));
