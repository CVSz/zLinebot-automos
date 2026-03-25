let dailyLoss = 0;

export function guard(tradeResult) {
  dailyLoss += tradeResult;

  if (dailyLoss < -50) {
    console.log("🛑 STOP TRADING (LOSS LIMIT)");
    return false;
  }

  return true;
}

export function resetDailyLoss() {
  dailyLoss = 0;
}
