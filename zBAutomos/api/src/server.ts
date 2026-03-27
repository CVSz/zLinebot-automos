import Fastify from "fastify";
import jwt from "@fastify/jwt";

import { registerAuthRoutes } from "./auth/routes";
import { registerMarketRoutes } from "./market/routes";
import { registerCopyRoutes } from "./copy/routes";
import { registerWsRoutes } from "./ws/routes";

declare const process: {
  env: Record<string, string | undefined>;
  exit: (code?: number) => never;
};

const app = Fastify({ logger: true });

app.register(jwt, {
  secret: process.env.JWT_SECRET ?? "zba-dev-secret",
});

app.decorate("authenticate", async (request: any, reply: any) => {
  try {
    await request.jwtVerify();
  } catch {
    reply.code(401).send({ error: "Unauthorized" });
  }
});

app.get("/health", async () => ({ status: "ok" }));

app.register(registerAuthRoutes, { prefix: "/auth" });
app.register(registerMarketRoutes, { prefix: "/market" });
app.register(registerCopyRoutes, { prefix: "/copy" });
app.register(registerWsRoutes, { prefix: "/ws" });

const start = async () => {
  const port = Number(process.env.PORT ?? 3000);
  await app.listen({ port, host: "0.0.0.0" });
};

start().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
