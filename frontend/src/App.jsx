import React from "react";
import CTA from "./components/CTA";
import LandingPage from "./pages/LandingPage";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";

function resolveRoute(pathname) {
  if (pathname.startsWith("/signup")) {
    return "signup";
  }

  if (pathname.startsWith("/login")) {
    return "login";
  }

  return "landing";
}

export default function App() {
  const route = resolveRoute(window.location.pathname);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {route === "landing" ? <LandingPage /> : null}
      {route === "signup" ? <SignupPage /> : null}
      {route === "login" ? <LoginPage /> : null}
      <CTA />
    </div>
  );
}
