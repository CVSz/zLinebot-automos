let dailyLoss = 0;
const MAX_DAILY_LOSS = Number(process.env.MAX_DAILY_LOSS || -500);

export function checkRisk(trade) {
  const pnl = Number(trade?.pnl || 0);
  dailyLoss += pnl;

  if (dailyLoss <= MAX_DAILY_LOSS) {
    console.log("🛑 STOP TRADING (LOSS LIMIT)");
    return false;
  }

  return true;
}

export function getRiskState() {
  return { dailyLoss, maxDailyLoss: MAX_DAILY_LOSS };
}

export function resetRisk() {
  dailyLoss = 0;
}
