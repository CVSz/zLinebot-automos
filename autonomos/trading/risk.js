export function riskControl(balance, price) {
  const riskPerTrade = Number(process.env.RISK_PER_TRADE || 0.01);
  const stopLossPercent = Number(process.env.STOP_LOSS_PCT || 0.02);

  const amount = (balance * riskPerTrade) / price;
  const stopLoss = price * (1 - stopLossPercent);

  return { amount, stopLoss };
}

