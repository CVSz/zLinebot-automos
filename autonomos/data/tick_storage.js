import fs from "node:fs";
import Redis from "ioredis";

export function startTickStorage({
  redisUrl = process.env.REDIS_URL,
  redisKey = "ticks:btcusdt",
  outputPath = "ticks.log",
  batchSize = 1_000,
  intervalMs = 5_000,
} = {}) {
  const redis = new Redis(redisUrl);

  return setInterval(async () => {
    const ticks = await redis.lrange(redisKey, 0, batchSize - 1);
    if (ticks.length === 0) return;

    const lines = ticks.reverse().join("\n") + "\n";
    fs.appendFileSync(outputPath, lines);
    await redis.ltrim(redisKey, batchSize, -1);
  }, intervalMs);
}
