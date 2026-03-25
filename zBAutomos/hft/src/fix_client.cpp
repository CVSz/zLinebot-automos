#include <quickfix/Application.h>
#include <quickfix/MessageCracker.h>
#include <quickfix/Session.h>
#include <quickfix/SocketInitiator.h>

class FixApp : public FIX::Application, public FIX::MessageCracker {
 public:
  void onCreate(const FIX::SessionID&) override {}
  void onLogon(const FIX::SessionID&) override {}
  void onLogout(const FIX::SessionID&) override {}

  void toAdmin(FIX::Message&, const FIX::SessionID&) override {}
  void toApp(FIX::Message&, const FIX::SessionID&) override {}

  void fromAdmin(const FIX::Message&, const FIX::SessionID&) override {}
  void fromApp(const FIX::Message& message, const FIX::SessionID& sessionID) override {
    crack(message, sessionID);
  }
};

int main() {
  // load QuickFIX settings
  // add NewOrderSingle builder / CancelReplace support
  // enforce heartbeat, sequence tracking, gap fill + resend handling
  // use separate MD and ORD sessions
  return 0;
}
