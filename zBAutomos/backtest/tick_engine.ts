export type Tick = { price: number; volume: number; ts: number };
export type Signal = "BUY" | "SELL" | "HOLD";

export class TickBacktest {
  private balance = 10000;
  private position = 0;
  private entry = 0;

  constructor(private readonly data: Tick[], private readonly fee = 0.001) {}

  run(strategy: (tick: Tick) => Signal): number {
    for (const tick of this.data) {
      const signal = strategy(tick);

      if (signal === "BUY" && this.position === 0) {
        this.position = this.balance / tick.price;
        this.entry = tick.price;
        this.balance = 0;
      }

      if (signal === "SELL" && this.position > 0) {
        this.balance = this.position * tick.price * (1 - this.fee);
        this.position = 0;
      }
    }

    if (this.position > 0) {
      const lastTick = this.data[this.data.length - 1];
      this.balance = this.position * lastTick.price * (1 - this.fee);
      this.position = 0;
    }

    return this.balance;
  }
}
