import Queue from "bull";
import { runUser } from "../trading/userEngine.js";

const redisUrl = process.env.REDIS_URL || "redis://127.0.0.1:6379";

export const tradingQueue = new Queue("trading", redisUrl);

tradingQueue.process(10, async (job) => runUser(job.data.userId, job.data.market || {}));

export function enqueueUserRun(userId, market = {}) {
  return tradingQueue.add({ userId, market });
}
