import React from "react";
import { LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, ResponsiveContainer } from "recharts";
import AnalyticsPanel from "./AnalyticsPanel";

export default function TradingDashboard({ data = [], trades = [], stats = {} }) {
  return (
    <div className="rounded-3xl border border-slate-800 bg-slate-900/80 p-6 shadow-xl">
      <h2 className="text-2xl font-bold text-cyan-300">📊 zLineBot Pro</h2>

      <div className="mt-4 h-80 w-full">
        <ResponsiveContainer>
          <LineChart data={data}>
            <CartesianGrid strokeDasharray="3 3" stroke="#1e293b" />
            <XAxis dataKey="time" stroke="#94a3b8" />
            <YAxis stroke="#94a3b8" />
            <Tooltip />
            <Line dataKey="price" stroke="#22d3ee" dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>

      <div className="mt-4">
        <AnalyticsPanel stats={stats} />
      </div>

      <div className="mt-4 space-y-1 text-slate-300">
        <h3 className="font-semibold text-slate-100">Trades</h3>
        {trades.length === 0 && <div className="text-slate-400">No trades yet.</div>}
        {trades.map((trade, index) => (
          <div key={`${trade.type}-${index}`} className="text-sm">
            {trade.type} @ {trade.price}
          </div>
        ))}
      </div>
    </div>
  );
}
