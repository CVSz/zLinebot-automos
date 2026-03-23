import React from "react";
import Hero from "./components/Hero";
import Features from "./components/Features";
import CTA from "./components/CTA";

export default function App() {
  return (
    <div className="font-sans text-slate-900">
      <Hero />
      <Features />
      <CTA />
    </div>
  );
}
