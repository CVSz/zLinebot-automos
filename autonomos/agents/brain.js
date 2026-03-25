import { optimize } from "../trading/optimizer.js";

export async function brain(prices) {
  const best = await optimize(prices);
  console.log("🧠 BEST CONFIG:", best);
  return best;
}
