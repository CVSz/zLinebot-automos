#include "mpsc_ring.hpp"

#include <cstdint>
#include <iostream>
#include <thread>

struct Tick {
  double bid;
  double ask;
  std::uint64_t ts;
};

int main() {
  MpscRing<Tick, 1024> q;

  std::thread producer1([&] {
    for (int i = 0; i < 100000; ++i) {
      while (!q.push(Tick{100.0 + i, 100.1 + i, static_cast<std::uint64_t>(i)})) {
      }
    }
  });

  std::thread consumer([&] {
    Tick t{};
    int seen = 0;
    while (seen < 100000) {
      if (q.pop(t)) {
        ++seen;
      }
    }
    std::cout << "consumed: " << seen << "\n";
  });

  producer1.join();
  consumer.join();
}
