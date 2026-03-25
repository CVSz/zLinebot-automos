#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <type_traits>

template <typename T, std::size_t CapacityPow2>
class MpscRing {
  static_assert((CapacityPow2 & (CapacityPow2 - 1)) == 0,
                "Capacity must be power of two");
  static_assert(std::is_trivially_copyable_v<T>, "T must be trivially copyable");

 public:
  MpscRing() {
    for (std::size_t i = 0; i < CapacityPow2; ++i) {
      cells_[i].seq.store(i, std::memory_order_relaxed);
    }
  }

  bool push(const T& value) noexcept {
    std::size_t pos = head_.load(std::memory_order_relaxed);

    for (;;) {
      Cell& cell = cells_[pos & mask_];
      const std::size_t seq = cell.seq.load(std::memory_order_acquire);
      const std::intptr_t diff = static_cast<std::intptr_t>(seq) -
                                 static_cast<std::intptr_t>(pos);

      if (diff == 0) {
        if (head_.compare_exchange_weak(pos, pos + 1, std::memory_order_acq_rel,
                                        std::memory_order_relaxed)) {
          cell.data = value;
          cell.seq.store(pos + 1, std::memory_order_release);
          return true;
        }
      } else if (diff < 0) {
        return false;  // full
      } else {
        pos = head_.load(std::memory_order_relaxed);
      }
    }
  }

  bool pop(T& out) noexcept {
    Cell& cell = cells_[tail_ & mask_];
    const std::size_t seq = cell.seq.load(std::memory_order_acquire);
    const std::intptr_t diff = static_cast<std::intptr_t>(seq) -
                               static_cast<std::intptr_t>(tail_ + 1);

    if (diff != 0) {
      return false;  // empty
    }

    out = cell.data;
    cell.seq.store(tail_ + CapacityPow2, std::memory_order_release);
    ++tail_;
    return true;
  }

  std::size_t size_approx() const noexcept {
    return head_.load(std::memory_order_relaxed) - tail_;
  }

 private:
  struct alignas(64) Cell {
    std::atomic<std::size_t> seq;
    T data;
  };

  static constexpr std::size_t mask_ = CapacityPow2 - 1;

  alignas(64) std::atomic<std::size_t> head_{0};
  alignas(64) std::size_t tail_{0};
  std::array<Cell, CapacityPow2> cells_{};
};
