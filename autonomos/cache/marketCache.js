import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://127.0.0.1:6379");
const PRICE_KEY_PREFIX = "market:price:";

export async function setCachedPrice(symbol, data, ttlSeconds = 2) {
  const key = `${PRICE_KEY_PREFIX}${symbol}`;
  await redis.set(key, JSON.stringify(data), "EX", ttlSeconds);
}

export async function getCachedPrice(symbol) {
  const key = `${PRICE_KEY_PREFIX}${symbol}`;
  const raw = await redis.get(key);
  return raw ? JSON.parse(raw) : null;
}
