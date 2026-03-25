#include <atomic>
#include <thread>

struct Tick {
  double bid;
  double ask;
  long ts;
};

std::atomic<bool> run{true};

void on_message(const Tick& t) {
  (void)t;
  // TODO: push into lock-free ring buffer.
}

int main() {
  while (run.load(std::memory_order_relaxed)) {
    // TODO: Poll vendor socket / bypass queue.
    // TODO: Decode payload to Tick and call on_message(t).
    std::this_thread::yield();
  }

  return 0;
}
