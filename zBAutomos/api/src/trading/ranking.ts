export type RankedUser = {
  id: string;
  pnl: number;
  drawdown: number;
};

export function rank(users: RankedUser[]): RankedUser[] {
  return [...users].sort((a, b) => {
    const scoreA = a.pnl - a.drawdown;
    const scoreB = b.pnl - b.drawdown;
    return scoreB - scoreA;
  });
}
