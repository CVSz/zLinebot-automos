import React, { useEffect, useMemo, useRef, useState } from "react";
import { Text, View } from "react-native";

const WS_URL = "wss://api.zeaz.dev/ws";

export default function App() {
  const [data, setData] = useState<{ balance?: number; pnl?: number }>({});
  const retry = useRef(0);
  const socket = useRef<WebSocket | null>(null);

  const authToken = useMemo(() => "replace-with-jwt-token", []);

  useEffect(() => {
    let active = true;

    const connect = () => {
      if (!active) return;

      socket.current = new WebSocket(`${WS_URL}?token=${encodeURIComponent(authToken)}`);

      socket.current.onmessage = (event) => {
        try {
          setData(JSON.parse(event.data));
        } catch {
          // Ignore malformed payloads from upstream.
        }
      };

      socket.current.onclose = () => {
        if (!active) return;

        retry.current += 1;
        const delayMs = Math.min(30_000, 1_000 * 2 ** retry.current);
        setTimeout(connect, delayMs);
      };

      socket.current.onopen = () => {
        retry.current = 0;
      };
    };

    connect();

    return () => {
      active = false;
      socket.current?.close();
    };
  }, [authToken]);

  return (
    <View style={{ padding: 20 }}>
      <Text>Balance: {data.balance ?? "--"}</Text>
      <Text>PnL: {data.pnl ?? "--"}</Text>
    </View>
  );
}
