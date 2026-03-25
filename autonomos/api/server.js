import express from "express";
import routes from "./routes.js";
import { startWebSocketServer } from "../ws/server.js";
import "../queue/tradingQueue.js";
import { askAI } from "../ai/chatgpt.js";
import { getRecentMessages, saveMessage } from "../memory/memory.js";

const app = express();
app.use(express.json());

app.post("/webhook", async (req, res) => {
  const user = req.body.userId || "line-user";
  const msg = req.body.message || "hello";

  await saveMessage(user, msg);
  const history = await getRecentMessages(user);

  const reply = await askAI(history.reverse().join("\n"));
  return res.json({ reply });
});

app.use("/api", routes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: "internal_error" });
});

const port = Number(process.env.PORT || 3300);
const wsPort = Number(process.env.WS_PORT || 4000);

app.listen(port, () => {
  startWebSocketServer(wsPort);
  console.log(`[autonomos] api listening on ${port} (ws:${wsPort})`);
});
