#pragma once

#include <quickfix/fix44/NewOrderSingle.h>
#include <quickfix/fix44/OrderCancelReplaceRequest.h>

#include <atomic>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <utility>

struct StrategyOrderIntent {
  std::string symbol;
  char side{FIX::Side_BUY};
  double qty{0.0};
  double limitPx{0.0};
  char tif{FIX::TimeInForce_IMMEDIATE_OR_CANCEL};
};

class FixOrderBuilder {
 public:
  explicit FixOrderBuilder(std::string prefix = "ZBA") : prefix_(std::move(prefix)) {}

  FIX44::NewOrderSingle buildNewOrderSingle(const StrategyOrderIntent& intent,
                                            std::string* clOrdIdOut = nullptr) {
    validate(intent);

    const std::string clOrdId = nextClOrdID();
    FIX44::NewOrderSingle order(FIX::ClOrdID(clOrdId), FIX::Side(intent.side),
                                FIX::TransactTime(FIX::UtcTimeStamp()),
                                FIX::OrdType(FIX::OrdType_LIMIT));

    order.set(FIX::Symbol(intent.symbol));
    order.set(FIX::OrderQty(intent.qty));
    order.set(FIX::Price(intent.limitPx));
    order.set(FIX::TimeInForce(intent.tif));

    if (clOrdIdOut != nullptr) {
      *clOrdIdOut = clOrdId;
    }
    return order;
  }

  FIX44::OrderCancelReplaceRequest buildCancelReplace(const std::string& origClOrdID,
                                                      const StrategyOrderIntent& intent,
                                                      std::string* clOrdIdOut = nullptr) {
    if (origClOrdID.empty()) {
      throw std::invalid_argument("origClOrdID must not be empty");
    }
    validate(intent);

    const std::string clOrdId = nextClOrdID();
    FIX44::OrderCancelReplaceRequest msg(
        FIX::OrigClOrdID(origClOrdID), FIX::ClOrdID(clOrdId), FIX::Side(intent.side),
        FIX::TransactTime(FIX::UtcTimeStamp()), FIX::OrdType(FIX::OrdType_LIMIT));

    msg.set(FIX::Symbol(intent.symbol));
    msg.set(FIX::OrderQty(intent.qty));
    msg.set(FIX::Price(intent.limitPx));
    msg.set(FIX::TimeInForce(intent.tif));

    if (clOrdIdOut != nullptr) {
      *clOrdIdOut = clOrdId;
    }
    return msg;
  }

 private:
  static void validate(const StrategyOrderIntent& intent) {
    if (intent.symbol.empty()) {
      throw std::invalid_argument("symbol must not be empty");
    }
    if (intent.qty <= 0.0) {
      throw std::invalid_argument("qty must be > 0");
    }
    if (intent.limitPx <= 0.0) {
      throw std::invalid_argument("limitPx must be > 0");
    }
    if (intent.side != FIX::Side_BUY && intent.side != FIX::Side_SELL) {
      throw std::invalid_argument("side must be FIX::Side_BUY or FIX::Side_SELL");
    }
  }

  std::string nextClOrdID() {
    const uint64_t n = seq_.fetch_add(1, std::memory_order_relaxed);
    return prefix_ + "-" + std::to_string(n);
  }

  std::string prefix_;
  std::atomic<uint64_t> seq_{1};
};
