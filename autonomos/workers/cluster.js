import cluster from "cluster";
import os from "os";
import { runUser } from "../trading/userEngine.js";

export function startWorker() {
  process.on("message", async (job) => {
    if (!job || !job.userId) return;
    await runUser(job.userId, job.market || {});
  });
}

if (cluster.isPrimary) {
  for (let i = 0; i < os.cpus().length; i += 1) {
    cluster.fork();
  }
} else {
  startWorker();
}
