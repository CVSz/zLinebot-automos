import type { FastifyInstance } from "fastify";

export async function registerWsRoutes(app: FastifyInstance) {
  app.get("/status", async () => ({ ws: "ready" }));
}
