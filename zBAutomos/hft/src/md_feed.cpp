#include <atomic>
#include <iostream>
#include <thread>

// Replace with vendor SDK (ITCH/OUCH/FAST/FIX-MD)
struct Tick {
  double bid;
  double ask;
  long ts;
};

std::atomic<bool> run{true};

void on_message(const Tick& t) {
  (void)t;
  // push into lock-free ring buffer (see ring.hpp)
}

int main() {
  // init NIC, set RSS queues, pin thread
  while (run.load(std::memory_order_relaxed)) {
    // poll socket / kernel-bypass queue
    // decode -> Tick t
    // on_message(t);
    std::this_thread::yield();
  }

  return 0;
}
