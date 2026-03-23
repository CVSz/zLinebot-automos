import React from "react";

const templates = [
  {
    title: "Founder Story",
    hook: "I built this after losing 19 hours/week to broken automations.",
    cta: "Steal this playbook"
  },
  {
    title: "Pain to Promise",
    hook: "If your funnel leaks leads, this page closes the gap.",
    cta: "Get instant access"
  },
  {
    title: "Challenge Funnel",
    hook: "7-day challenge onboarding for SaaS communities.",
    cta: "Launch my challenge"
  }
];

export default function ViralTemplates() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-10">
      <h3 className="text-2xl font-bold text-white">Viral template blocks</h3>
      <p className="mt-2 text-slate-300">Plug these into your offers and iterate quickly with AI-generated copy.</p>
      <div className="mt-6 grid gap-4 md:grid-cols-3">
        {templates.map((template) => (
          <div key={template.title} className="rounded-2xl border border-cyan-500/20 bg-slate-900 p-5">
            <p className="text-xs font-semibold uppercase tracking-wider text-cyan-300">{template.title}</p>
            <p className="mt-3 text-lg font-semibold text-slate-50">{template.hook}</p>
            <button className="mt-5 rounded-lg bg-slate-800 px-4 py-2 text-sm font-semibold text-cyan-200">{template.cta}</button>
          </div>
        ))}
      </div>
    </section>
  );
}
