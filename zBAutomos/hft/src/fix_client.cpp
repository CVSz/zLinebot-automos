#include <quickfix/Application.h>
#include <quickfix/FileLog.h>
#include <quickfix/FileStore.h>
#include <quickfix/MessageCracker.h>
#include <quickfix/Session.h>
#include <quickfix/SessionSettings.h>
#include <quickfix/SocketInitiator.h>
#include <quickfix/fix44/ExecutionReport.h>
#include <quickfix/fix44/NewOrderSingle.h>
#include <quickfix/fix44/OrderCancelReplaceRequest.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

class FixClient final : public FIX::Application, public FIX::MessageCracker {
 public:
  void onCreate(const FIX::SessionID&) override {}

  void onLogon(const FIX::SessionID& sessionID) override {
    sessionID_ = sessionID;
    loggedOn_.store(true, std::memory_order_release);
    std::cout << "FIX logon: " << sessionID << "\n";
  }

  void onLogout(const FIX::SessionID&) override {
    loggedOn_.store(false, std::memory_order_release);
    std::cout << "FIX logout\n";
  }

  void toAdmin(FIX::Message&, const FIX::SessionID&) override {}

  void toApp(FIX::Message& message, const FIX::SessionID&) override {
    if (!FIX::Session::lookupSession(sessionID_)) {
      throw std::runtime_error("FIX session unavailable");
    }
    std::cout << "OUT: " << message.toString() << "\n";
  }

  void fromAdmin(const FIX::Message&, const FIX::SessionID&) override {}

  void fromApp(const FIX::Message& message, const FIX::SessionID& sessionID) override {
    crack(message, sessionID);
  }

  void onMessage(const FIX44::ExecutionReport& msg, const FIX::SessionID&) override {
    std::cout << "EXECUTION_REPORT: " << msg.toString() << "\n";
  }

  bool isLoggedOn() const { return loggedOn_.load(std::memory_order_acquire); }

  FIX::SessionID sessionID() const { return sessionID_; }

 private:
  std::atomic<bool> loggedOn_{false};
  FIX::SessionID sessionID_;
};

static std::string nextClOrdID() {
  static std::atomic<uint64_t> seq{1};
  return "ZBA-" + std::to_string(seq.fetch_add(1, std::memory_order_relaxed));
}

static FIX::UtcTimeStamp nowUtc() { return FIX::UtcTimeStamp(); }

static void sendNewOrderSingle(const FIX::SessionID& sid, const std::string& symbol, char side,
                               double qty, double limitPx) {
  FIX44::NewOrderSingle order(FIX::ClOrdID(nextClOrdID()), FIX::Side(side),
                              FIX::TransactTime(nowUtc()), FIX::OrdType(FIX::OrdType_LIMIT));

  order.set(FIX::Symbol(symbol));
  order.set(FIX::OrderQty(qty));
  order.set(FIX::Price(limitPx));
  order.set(FIX::TimeInForce(FIX::TimeInForce_IMMEDIATE_OR_CANCEL));

  if (!FIX::Session::sendToTarget(order, sid)) {
    throw std::runtime_error("sendToTarget(NewOrderSingle) failed");
  }
}

static void sendCancelReplace(const FIX::SessionID& sid, const std::string& origClOrdID,
                              const std::string& symbol, char side, double qty, double newPx) {
  FIX44::OrderCancelReplaceRequest msg(
      FIX::OrigClOrdID(origClOrdID), FIX::ClOrdID(nextClOrdID()), FIX::Side(side),
      FIX::TransactTime(nowUtc()), FIX::OrdType(FIX::OrdType_LIMIT));

  msg.set(FIX::Symbol(symbol));
  msg.set(FIX::OrderQty(qty));
  msg.set(FIX::Price(newPx));
  msg.set(FIX::TimeInForce(FIX::TimeInForce_IMMEDIATE_OR_CANCEL));

  if (!FIX::Session::sendToTarget(msg, sid)) {
    throw std::runtime_error("sendToTarget(OrderCancelReplaceRequest) failed");
  }
}

int main() {
  try {
    const std::string cfg = "config/fix_client.cfg";

    FIX::SessionSettings settings(cfg);
    FixClient app;
    FIX::FileStoreFactory storeFactory(settings);
    FIX::FileLogFactory logFactory(settings);

    FIX::SocketInitiator initiator(app, storeFactory, settings, logFactory);
    initiator.start();

    while (!app.isLoggedOn()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    const auto sid = app.sessionID();

    sendNewOrderSingle(sid, "BTCUSDT", FIX::Side_BUY, 0.01, 65000.0);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    sendCancelReplace(sid, "ZBA-1", "BTCUSDT", FIX::Side_BUY, 0.01, 64950.0);

    std::this_thread::sleep_for(std::chrono::seconds(2));
    initiator.stop();
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "fatal: " << e.what() << "\n";
    return 1;
  }
}
