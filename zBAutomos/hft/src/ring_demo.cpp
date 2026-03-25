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
  constexpr int kPerProducer = 100000;

  std::thread producer1([&] {
    for (int i = 0; i < kPerProducer; ++i) {
      while (!q.push(Tick{100.0 + i, 100.1 + i, static_cast<std::uint64_t>(i)})) {
      }
    }
  });

  std::thread producer2([&] {
    for (int i = 0; i < kPerProducer; ++i) {
      while (!q.push(Tick{200.0 + i, 200.1 + i,
                          static_cast<std::uint64_t>(kPerProducer + i)})) {
      }
    }
  });

  std::thread consumer([&] {
    Tick t{};
    int seen = 0;
    while (seen < (kPerProducer * 2)) {
      if (q.pop(t)) {
        ++seen;
      }
    }
    std::cout << "consumed: " << seen << "\n";
  });

  producer1.join();
  producer2.join();
  consumer.join();
}
