import { WebSocketServer } from "ws";

let wss;

export function startWebSocketServer(port = Number(process.env.WS_PORT || 4000)) {
  if (wss) return wss;

  wss = new WebSocketServer({ port });
  wss.on("connection", (socket) => {
    socket.send(JSON.stringify({ type: "CONNECTED", ts: Date.now() }));
  });

  return wss;
}

export function broadcast(data) {
  if (!wss) return;

  const payload = JSON.stringify(data);
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(payload);
    }
  });
}
