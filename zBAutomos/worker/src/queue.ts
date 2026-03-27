export type Task = { id: string; run: () => Promise<void> };

export class TaskQueue {
  private queue: Task[] = [];
  private active = false;

  enqueue(task: Task) {
    this.queue.push(task);
    this.drain().catch(() => undefined);
  }

  private async drain() {
    if (this.active) return;
    this.active = true;

    try {
      while (this.queue.length > 0) {
        const task = this.queue.shift();
        if (!task) continue;
        await task.run();
      }
    } finally {
      this.active = false;
      if (this.queue.length > 0) {
        this.drain().catch(() => undefined);
      }
    }
  }
}
