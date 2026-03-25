export type Position = { symbol: string; qty: number; price: number };

export class RiskEngine {
  private maxDailyLoss = -1000;
  private maxExposure = 50000;
  private pnl = 0;
  private returns: number[] = [];

  constructor(private positions: Position[]) {}

  updatePnL(delta: number) {
    this.pnl += delta;
  }

  updateReturns(ret: number, window = 2000) {
    this.returns.push(ret);
    if (this.returns.length > window) {
      this.returns.shift();
    }
  }

  checkPreTrade(notional: number) {
    if (this.pnl <= this.maxDailyLoss) {
      throw new Error("HALT: loss limit");
    }

    const exposure = this.exposure();
    if (exposure + notional > this.maxExposure) {
      throw new Error("HALT: exposure");
    }

    if (this.returns.length > 20 && this.var95(this.returns) < -0.03) {
      throw new Error("HALT: VaR breach");
    }
  }

  exposure() {
    return this.positions.reduce((acc, p) => acc + Math.abs(p.qty * p.price), 0);
  }

  var95(returns: number[]) {
    const sorted = [...returns].sort((a, b) => a - b);
    return sorted[Math.floor(0.05 * sorted.length)];
  }
}
