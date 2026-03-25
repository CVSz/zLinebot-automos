const ACTIONS = ["BUY", "SELL", "HOLD"];

export class RLAgent {
  constructor({ alpha = 0.1, gamma = 0.9, epsilon = 0.2 } = {}) {
    this.q = {};
    this.alpha = alpha;
    this.gamma = gamma;
    this.epsilon = epsilon;
  }

  getState(data) {
    return JSON.stringify({
      rsi: Math.round(Number(data?.rsi ?? 50)),
      trend: Number(data?.trend ?? 0) >= 0 ? "UP" : "DOWN",
      macd: Number(data?.macd ?? 0) >= 0 ? "POS" : "NEG",
    });
  }

  chooseAction(state) {
    if (Math.random() < this.epsilon) {
      return ACTIONS[Math.floor(Math.random() * ACTIONS.length)];
    }

    const stateValues = this.q[state];
    if (!stateValues) return "HOLD";

    return ACTIONS.reduce((bestAction, action) => {
      const candidate = stateValues[action] ?? 0;
      const best = stateValues[bestAction] ?? 0;
      return candidate > best ? action : bestAction;
    }, "HOLD");
  }

  update(state, action, reward, nextState) {
    const currentState = this.q[state] || { BUY: 0, SELL: 0, HOLD: 0 };
    const nextValues = this.q[nextState] || { BUY: 0, SELL: 0, HOLD: 0 };
    const nextMax = Math.max(nextValues.BUY, nextValues.SELL, nextValues.HOLD);

    const old = currentState[action] ?? 0;
    const learned = old + this.alpha * (reward + this.gamma * nextMax - old);

    this.q[state] = { ...currentState, [action]: learned };
  }
}
