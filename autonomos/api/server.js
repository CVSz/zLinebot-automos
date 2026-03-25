import express from "express";
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

const port = Number(process.env.PORT || 3300);
app.listen(port, () => console.log(`[autonomos] api listening on ${port}`));

