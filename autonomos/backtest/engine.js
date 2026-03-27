const DEFAULT_STARTING_BALANCE = 10_000;

function safeNumber(value, fallback = 0) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
}

export class BacktestEngine {
  constructor(strategy, data = [], options = {}) {
    this.strategy = strategy;
    this.data = Array.isArray(data) ? data : [];
    this.startingBalance = safeNumber(options.startingBalance, DEFAULT_STARTING_BALANCE);
    this.feeRate = safeNumber(options.feeRate, 0.001);
    this.slippageRate = safeNumber(options.slippageRate, 0.0005);
    this.stopLossPercent = safeNumber(options.stopLossPercent, 0);
    this.takeProfitPercent = safeNumber(options.takeProfitPercent, 0);

    this.balance = this.startingBalance;
    this.position = 0;
    this.entry = 0;
    this.entryTime = null;
    this.trades = [];
    this.equityCurve = [];
    this.returns = [];
  }

  run() {
    if (typeof this.strategy !== "function" || this.data.length === 0) {
      return this.results();
    }

    for (let i = 0; i < this.data.length; i++) {
      const candle = this.data[i];
      const price = safeNumber(candle?.price);
      if (price <= 0) continue;

      const previousEquity = this.currentEquity(price);
      const signal = this.strategy(candle, this.getState(candle, i));

      if (signal === "BUY" && this.position === 0 && this.balance > 0) {
        this.openPosition(price, candle, i);
      }

      if (signal === "SELL" && this.position > 0) {
        this.closePosition(price, candle, i, "signal");
      }

      if (this.position > 0) {
        if (this.shouldStopLoss(price)) {
          this.closePosition(price, candle, i, "stop_loss");
        } else if (this.shouldTakeProfit(price)) {
          this.closePosition(price, candle, i, "take_profit");
        }
      }

      const equity = this.currentEquity(price);
      this.equityCurve.push({ index: i, time: candle?.time || i, equity });

      if (i > 0 && previousEquity > 0) {
        this.returns.push((equity - previousEquity) / previousEquity);
      }
    }

    const lastPrice = safeNumber(this.data[this.data.length - 1]?.price, 0);
    if (this.position > 0 && lastPrice > 0) {
      this.closePosition(lastPrice, this.data[this.data.length - 1], this.data.length - 1, "eod");
    }

    return this.results();
  }

  shouldStopLoss(price) {
    return this.entry > 0 && this.stopLossPercent > 0 && price <= this.entry * (1 - this.stopLossPercent);
  }

  shouldTakeProfit(price) {
    return this.entry > 0 && this.takeProfitPercent > 0 && price >= this.entry * (1 + this.takeProfitPercent);
  }

  openPosition(price, candle, index) {
    const execPrice = price * (1 + this.slippageRate);
    const fee = this.balance * this.feeRate;
    const capital = Math.max(0, this.balance - fee);
    this.position = capital / execPrice;
    this.balance = 0;
    this.entry = execPrice;
    this.entryTime = candle?.time || index;

    this.trades.push({ type: "BUY", price: execPrice, fee, index, time: candle?.time || index });
  }

  closePosition(price, candle, index, reason) {
    const execPrice = price * (1 - this.slippageRate);
    const gross = this.position * execPrice;
    const fee = gross * this.feeRate;
    this.balance = Math.max(0, gross - fee);

    const pnl = this.entry > 0 ? (execPrice - this.entry) * this.position : 0;
    this.trades.push({
      type: "SELL",
      price: execPrice,
      fee,
      reason,
      index,
      pnl,
      entry: this.entry,
      entryTime: this.entryTime,
      time: candle?.time || index,
    });

    this.position = 0;
    this.entry = 0;
    this.entryTime = null;
  }

  currentEquity(markPrice) {
    return this.balance + this.position * markPrice;
  }

  getState(candle, index) {
    return {
      index,
      candle,
      balance: this.balance,
      position: this.position,
      entry: this.entry,
      trades: this.trades,
      equityCurve: this.equityCurve,
    };
  }

  results() {
    const endingBalance = this.equityCurve.length
      ? this.equityCurve[this.equityCurve.length - 1].equity
      : this.balance;
    const totalReturn = this.startingBalance > 0 ? (endingBalance - this.startingBalance) / this.startingBalance : 0;

    return {
      startingBalance: this.startingBalance,
      endingBalance,
      profit: endingBalance - this.startingBalance,
      totalReturn,
      trades: this.trades,
      equityCurve: this.equityCurve,
      returns: this.returns,
      metrics: calculateMetrics(this.returns, this.equityCurve, this.trades),
    };
  }
}

export function sharpe(returns = [], periodsPerYear = 365) {
  if (!returns.length) return 0;
  const avg = returns.reduce((sum, value) => sum + value, 0) / returns.length;
  const variance = returns.reduce((sum, value) => sum + (value - avg) ** 2, 0) / returns.length;
  const std = Math.sqrt(variance);
  if (!std) return 0;
  return (avg / std) * Math.sqrt(periodsPerYear);
}

export function maxDrawdown(equityCurve = []) {
  if (!equityCurve.length) return 0;
  let peak = equityCurve[0].equity;
  let maxDd = 0;

  for (const point of equityCurve) {
    peak = Math.max(peak, point.equity);
    if (peak <= 0) continue;
    const dd = (peak - point.equity) / peak;
    maxDd = Math.max(maxDd, dd);
  }

  return maxDd;
}

export function calculateMetrics(returns = [], equityCurve = [], trades = []) {
  let positive = 0;
  for (let i = 0; i < returns.length; i += 1) {
    if (returns[i] > 0) positive += 1;
  }
  const tradeStats = calculateTradeStats(trades);
  return {
    sharpe: sharpe(returns),
    maxDrawdown: maxDrawdown(equityCurve),
    periods: returns.length,
    positivePeriods: positive,
    winRateByPeriod: returns.length ? positive / returns.length : 0,
    ...tradeStats,
  };
}

export function calculateTradeStats(trades = []) {
  let totalTrades = 0;
  let winningTrades = 0;
  let grossProfit = 0;
  let grossLoss = 0;

  for (let i = 0; i < trades.length; i += 1) {
    const trade = trades[i];
    if (trade?.type !== "SELL") continue;

    totalTrades += 1;
    const pnl = safeNumber(trade.pnl);
    if (pnl > 0) {
      winningTrades += 1;
      grossProfit += pnl;
      continue;
    }

    if (pnl < 0) {
      grossLoss += Math.abs(pnl);
    }
  }

  return {
    totalTrades,
    winningTrades,
    tradeWinRate: totalTrades ? winningTrades / totalTrades : 0,
    profitFactor: grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? Infinity : 0,
  };
}
