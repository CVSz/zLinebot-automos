import { run } from "./trading/engine.js";

export async function loop() {
  console.log("🤖 Running autonomous system...");
  await run();
}

if (String(process.env.AUTONOMOUS_LOOP || "false") === "true") {
  setInterval(loop, 60000);
}
