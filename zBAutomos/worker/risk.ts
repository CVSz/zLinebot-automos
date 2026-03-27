export function enforceRisk(maxPosition: number, requested: number): number {
  if (maxPosition < 0) {
    throw new Error("maxPosition must be non-negative");
  }

  if (requested > maxPosition) return maxPosition;
  if (requested < -maxPosition) return -maxPosition;
  return requested;
}
