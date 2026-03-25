export type Signal = "BUY" | "SELL" | "HOLD";

export function aggregate(signals: Signal[]) {
  const score = signals.reduce((acc, signal) => {
    if (signal === "BUY") return acc + 1;
    if (signal === "SELL") return acc - 1;
    return acc;
  }, 0);

  if (score > 1) return "BUY" as const;
  if (score < -1) return "SELL" as const;
  return "HOLD" as const;
}
