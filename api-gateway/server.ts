import express from "express";
import helmet from "helmet";

const app = express();

app.use(helmet());
app.use(express.json({ limit: "1mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "api-gateway" });
});

app.listen(3000, () => {
  console.log("API Gateway listening on :3000");
});
