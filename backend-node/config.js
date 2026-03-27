const NODE_ENV = process.env.NODE_ENV || "development";

const toInt = (value, fallback) => {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

const splitCsv = (value, fallback) => {
  const raw = String(value || "").trim();
  if (!raw) return fallback;
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
};

export const config = {
  nodeEnv: NODE_ENV,
  stripeSecretKey: String(process.env.STRIPE_SECRET_KEY || "").trim(),
  stripeWebhookSecret: String(process.env.STRIPE_WEBHOOK_SECRET || "").trim(),
  stripePriceId: String(process.env.STRIPE_PRICE_ID || "").trim(),
  appBaseUrl: String(process.env.APP_BASE_URL || "https://yourdomain.com").trim(),
  serverPort: toInt(process.env.PORT, 3000),
  webhookPort: toInt(process.env.WEBHOOK_PORT, 3001),
  allowedOrigins: splitCsv(process.env.CORS_ORIGINS, ["*"]),
  chatMaxLength: toInt(process.env.CHAT_MAX_LENGTH, 1200),
};

export const hasStripeCheckoutConfig =
  Boolean(config.stripeSecretKey) && Boolean(config.stripePriceId);

export const hasStripeWebhookConfig =
  Boolean(config.stripeSecretKey) && Boolean(config.stripeWebhookSecret);
