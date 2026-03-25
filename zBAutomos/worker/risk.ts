export function enforceRisk(maxPosition: number, requested: number): number {
  return Math.min(maxPosition, requested);
}
