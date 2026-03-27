# backend-node

Minimal Node services for Stripe checkout (`server.js`) and Stripe webhook processing (`webhook.js`).

## Environment variables

- `STRIPE_SECRET_KEY` (required for checkout/webhook routes)
- `STRIPE_PRICE_ID` (required for checkout route)
- `STRIPE_WEBHOOK_SECRET` (required for webhook route)
- `APP_BASE_URL` (optional, default `https://yourdomain.com`)
- `PORT` (optional, default `3000`)
- `WEBHOOK_PORT` (optional, default `3001`)
- `CORS_ORIGINS` (optional CSV, default `*`)
- `CHAT_MAX_LENGTH` (optional, default `1200`)

When Stripe variables are missing, endpoints return `503` instead of crashing at startup.
