import type { FastifyInstance } from "fastify";

type LoginBody = { userId: string };

export async function registerAuthRoutes(app: FastifyInstance) {
  app.post<{ Body: LoginBody }>("/login", async (request, reply) => {
    const { userId } = request.body;
    if (!userId?.trim()) {
      return reply.code(400).send({ error: "userId is required" });
    }

    const token = await app.jwt.sign({ sub: userId, role: "trader" });
    return { token };
  });
}
