export function VaR(returns, confidence = 0.95) {
  if (!returns.length) return 0;
  const sorted = [...returns].sort((a, b) => a - b);
  const index = Math.max(0, Math.floor((1 - confidence) * sorted.length));
  return sorted[index];
}
