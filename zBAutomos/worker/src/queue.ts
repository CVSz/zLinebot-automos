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

    while (this.queue.length > 0) {
      const task = this.queue.shift();
      if (!task) continue;
      await task.run();
    }

    this.active = false;
  }
}
