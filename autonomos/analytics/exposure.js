export function exposure(positions) {
  return positions.reduce((acc, position) => acc + Math.abs(Number(position.size || 0)), 0);
}
