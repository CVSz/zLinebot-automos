import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL || "redis://127.0.0.1:6379");

export async function saveMessage(userId, message) {
  await redis.lpush(`chat:${userId}`, message);
  await redis.ltrim(`chat:${userId}`, 0, 50);
}

export async function getRecentMessages(userId, limit = 10) {
  return redis.lrange(`chat:${userId}`, 0, limit - 1);
}

