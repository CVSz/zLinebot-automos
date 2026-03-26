export function exposure(positions) {
  if (!Array.isArray(positions)) {
    throw new Error("positions must be an array");
  }

  return positions.reduce((acc, position) => acc + Math.abs(Number(position.size ?? 0)), 0);
}

export function netExposure(positions) {
  if (!Array.isArray(positions)) {
    throw new Error("positions must be an array");
  }

  return positions.reduce((acc, position) => acc + Number(position.size ?? 0), 0);
}
