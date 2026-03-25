import type { FastifyInstance } from "fastify";

type SubscribeBody = {
  leaderId: string;
  plan: "basic" | "pro";
  stripePaymentMethodId: string;
};

export async function registerCopyRoutes(app: FastifyInstance) {
  app.post<{ Body: SubscribeBody }>("/subscribe", async (request, reply) => {
    const { leaderId, plan, stripePaymentMethodId } = request.body;

    if (!leaderId || !stripePaymentMethodId) {
      return reply.code(400).send({ error: "Missing subscription params" });
    }

    return {
      ok: true,
      leaderId,
      plan,
      status: "stripe_intent_created",
    };
  });
}
