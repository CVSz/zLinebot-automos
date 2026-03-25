#include <immintrin.h>
#include <sched.h>
#include <unistd.h>

#include <iostream>
#include <thread>

struct alignas(64) OB {
  double bid;
  double ask;
};

static inline void pin_cpu(int cpu) {
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(cpu, &set);
  sched_setaffinity(0, sizeof(set), &set);
}

static inline void busy_pause() { _mm_pause(); }

int main() {
  pin_cpu(2);  // isolate core
  OB ob{100.0, 100.02};

  while (true) {
    _mm_prefetch(reinterpret_cast<const char*>(&ob), _MM_HINT_T0);
    const double mid = (ob.bid + ob.ask) * 0.5;
    const double spread = ob.ask - ob.bid;

    if (__builtin_expect(spread > 0.01, 0)) {
      // write to lock-free queue for FIX sender
      // minimal work in hot path
      std::cout << mid << '\n';
    }

    busy_pause();
  }

  return 0;
}
