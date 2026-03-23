import React from "react";

export default function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-6 pb-10 pt-20 md:pt-24">
      <span className="rounded-full border border-cyan-400/40 bg-cyan-500/10 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-cyan-300">
        Viral Template Engine
      </span>
      <h1 className="mt-5 max-w-4xl text-4xl font-black leading-tight text-white md:text-6xl">
        Launch your AI growth funnel in one day, not one quarter.
      </h1>
      <p className="mt-6 max-w-2xl text-lg text-slate-300">
        Landing, signup, login, and chat-ready flows wired to your API endpoints
        with a production Docker stack.
      </p>
      <div className="mt-8 flex flex-wrap gap-4">
        <a className="rounded-xl bg-cyan-500 px-6 py-3 font-semibold text-slate-900 hover:bg-cyan-400" href="/signup">
          Start Free
        </a>
        <a className="rounded-xl border border-slate-600 px-6 py-3 font-semibold text-slate-200 hover:border-cyan-300 hover:text-cyan-300" href="/login">
          Login
        </a>
      </div>
    </section>
  );
}
