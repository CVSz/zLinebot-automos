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
  // TODO: load QuickFIX settings, enable persistence, heartbeat, and resend handling.
  return 0;
}
