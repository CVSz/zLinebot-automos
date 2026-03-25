export function findArb(priceA, priceB, { minEdge = 10, takerFee = 0 } = {}) {
  const grossDiff = Number(priceA) - Number(priceB);
  const netDiff = Math.abs(grossDiff) - takerFee;

  if (netDiff <= minEdge) return null;

  return grossDiff > 0
    ? { sell: "A", buy: "B", expectedEdge: netDiff }
    : { sell: "B", buy: "A", expectedEdge: netDiff };
}
