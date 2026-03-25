import WebSocket from "ws";
import Redis from "ioredis";

export function startTickCollector({
  streamUrl = "wss://stream.binance.com:9443/ws/btcusdt@trade",
  redisUrl = process.env.REDIS_URL,
  redisKey = "ticks:btcusdt",
} = {}) {
  const redis = new Redis(redisUrl);
  const socket = new WebSocket(streamUrl);

  socket.on("message", async (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      const tick = {
        symbol: (data.s || "BTCUSDT").toUpperCase(),
        price: Number(data.p),
        quantity: Number(data.q),
        tradeTime: Number(data.T),
        receivedAt: Date.now(),
      };

      await redis.lpush(redisKey, JSON.stringify(tick));
    } catch (error) {
      console.error("[tick_collector] parse/store failure", error.message);
    }
  });

  socket.on("close", () => {
    setTimeout(() => startTickCollector({ streamUrl, redisUrl, redisKey }), 1_000);
  });

  return { socket, redis };
}
