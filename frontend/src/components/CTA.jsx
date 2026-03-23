import React from "react";

export default function CTA() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-14">
      <div className="rounded-3xl border border-cyan-400/30 bg-gradient-to-r from-cyan-500/20 to-blue-500/10 p-8 text-center shadow-2xl shadow-cyan-900/20">
        <h3 className="text-3xl font-black text-white">Deploy today on local VM or cloud VM</h3>
        <p className="mx-auto mt-3 max-w-3xl text-slate-200">
          Self-signed TLS by default, backup and monitoring scripts included, and easy upgrade to Let's Encrypt.
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <a className="rounded-xl bg-cyan-400 px-5 py-2 font-bold text-slate-900" href="/signup">
            Create account
          </a>
          <a className="rounded-xl border border-slate-500 px-5 py-2 font-bold text-slate-100" href="/admin/">
            Open Admin Panel
          </a>
          <a className="rounded-xl border border-slate-500 px-5 py-2 font-bold text-slate-100" href="/devops/">
            Open DevOps Panel
          </a>
        </div>
      </div>
    </section>
  );
}
