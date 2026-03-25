import type { FastifyInstance } from "fastify";

export async function registerMarketRoutes(app: FastifyInstance) {
  app.get("/snapshot", async () => {
    return {
      symbol: "BTCUSDT",
      bid: 100.0,
      ask: 100.02,
      ts: Date.now(),
    };
  });
}
