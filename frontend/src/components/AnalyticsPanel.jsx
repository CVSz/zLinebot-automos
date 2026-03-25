import React from "react";

export default function AnalyticsPanel({ stats }) {
  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-900/70 p-4 text-slate-200">
      <h3 className="text-lg font-semibold text-cyan-300">📊 Performance</h3>
      <div className="mt-3 grid gap-2 text-sm sm:grid-cols-3">
        <p>Sharpe: <span className="font-semibold text-slate-100">{stats?.sharpe ?? 0}</span></p>
        <p>Drawdown: <span className="font-semibold text-slate-100">{stats?.drawdown ?? 0}</span></p>
        <p>Win Rate: <span className="font-semibold text-slate-100">{stats?.winRate ?? 0}</span></p>
      </div>
    </div>
  );
}
