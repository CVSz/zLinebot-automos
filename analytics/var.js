export function VaR(returns, confidence = 0.95) {
  if (!Array.isArray(returns) || returns.length < 2) {
    throw new Error("returns must contain at least two observations");
  }
  if (confidence <= 0 || confidence >= 1) {
    throw new Error("confidence must be between 0 and 1");
  }

  const sorted = [...returns].sort((a, b) => a - b);
  const tailProbability = 1 - confidence;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.floor(tailProbability * sorted.length)));
  return sorted[index];
}

export function cVaR(returns, confidence = 0.95) {
  const varValue = VaR(returns, confidence);
  const tail = returns.filter((value) => value <= varValue);
  if (tail.length === 0) {
    return varValue;
  }
  return tail.reduce((acc, value) => acc + value, 0) / tail.length;
}
