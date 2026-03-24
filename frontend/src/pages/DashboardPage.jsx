import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  createBroadcast,
  createCheckout,
  createTemplate,
  getCampaigns,
  getLeads,
  getMe,
  getRevenueDaily,
  getStats,
  getTemplates,
  patchLead
} from "../lib/api";

const pipeline = ["new", "cold", "warm", "hot", "closed"];

function formatMoney(value) {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0
  }).format(value || 0);
}

function readSession() {
  try {
    const raw = localStorage.getItem("zline.session");
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function actionsForStatus(status) {
  const index = pipeline.indexOf(status);
  if (index === -1) {
    return [];
  }

  return [pipeline[index - 1], pipeline[index + 1]].filter(Boolean);
}

function formatDateTime(value) {
  if (!value) {
    return "—";
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return "—";
  }

  return parsed.toLocaleString();
}

export default function DashboardPage() {
  const [session, setSession] = useState(() => readSession());
  const [profile, setProfile] = useState(null);
  const [stats, setStats] = useState(null);
  const [leads, setLeads] = useState([]);
  const [templates, setTemplates] = useState([]);
  const [campaigns, setCampaigns] = useState([]);
  const [dailyRevenue, setDailyRevenue] = useState([]);
  const [statusFilter, setStatusFilter] = useState("all");
  const [leadSearch, setLeadSearch] = useState("");
  const [leadSort, setLeadSort] = useState("updated_desc");
  const [templateDraft, setTemplateDraft] = useState({ name: "", message: "" });
  const [broadcastDraft, setBroadcastDraft] = useState({ name: "Promo Blast", message: "", target_status: "" });
  const [feedback, setFeedback] = useState({ tone: "info", text: "" });
  const [loading, setLoading] = useState(true);
  const [actionBusy, setActionBusy] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [lastSyncAt, setLastSyncAt] = useState("");

  const token = session?.access_token;
  const tenantId = session?.user?.tenant_id;

  const setError = useCallback((message) => {
    setFeedback({ tone: "error", text: message || "Something went wrong." });
  }, []);

  const setSuccess = useCallback((message) => {
    setFeedback({ tone: "success", text: message || "Done." });
  }, []);

  const handleAuthFailure = useCallback((message) => {
    setError(message);
    localStorage.removeItem("zline.session");
    setSession(null);
    window.location.href = "/login";
  }, [setError]);

  const loadDashboard = useCallback(async (options = {}) => {
    if (!token || !tenantId) {
      window.location.href = "/login";
      return;
    }

    if (!options.background) {
      setLoading(true);
    }

    try {
      const [me, statsData, leadsData, templatesData, campaignsData, revenueData] = await Promise.all([
        getMe(token),
        getStats(token, tenantId),
        getLeads(token, tenantId),
        getTemplates(token, tenantId),
        getCampaigns(token, tenantId),
        getRevenueDaily(token, tenantId)
      ]);

      setProfile(me);
      setStats(statsData);
      setLeads(leadsData);
      setTemplates(templatesData);
      setCampaigns(campaignsData);
      setDailyRevenue(revenueData);
      setLastSyncAt(new Date().toISOString());

      if (!options.keepFeedback) {
        setFeedback({ tone: "info", text: "" });
      }
    } catch (error) {
      if ((error.message || "").toLowerCase().includes("credentials")) {
        handleAuthFailure(error.message);
        return;
      }

      setError(error.message);
    } finally {
      setLoading(false);
    }
  }, [handleAuthFailure, setError, tenantId, token]);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  useEffect(() => {
    if (!autoRefresh || !token || !tenantId) {
      return undefined;
    }

    const interval = setInterval(() => {
      loadDashboard({ background: true, keepFeedback: true });
    }, 30000);

    return () => clearInterval(interval);
  }, [autoRefresh, loadDashboard, tenantId, token]);

  const visibleLeads = useMemo(() => {
    let filtered = statusFilter === "all" ? leads : leads.filter((lead) => lead.status === statusFilter);

    if (leadSearch.trim()) {
      const needle = leadSearch.trim().toLowerCase();
      filtered = filtered.filter((lead) => (
        [lead.name, lead.phone, lead.user_id, lead.interest]
          .filter(Boolean)
          .some((value) => String(value).toLowerCase().includes(needle))
      ));
    }

    return [...filtered].sort((a, b) => {
      if (leadSort === "score_desc") {
        return (b.score || 0) - (a.score || 0);
      }
      if (leadSort === "score_asc") {
        return (a.score || 0) - (b.score || 0);
      }

      const aTime = new Date(a.updated_at || 0).getTime();
      const bTime = new Date(b.updated_at || 0).getTime();
      if (leadSort === "updated_asc") {
        return aTime - bTime;
      }
      return bTime - aTime;
    });
  }, [leadSearch, leadSort, leads, statusFilter]);

  const revenuePeak = useMemo(() => Math.max(1, ...dailyRevenue.map((point) => point.revenue || 0)), [dailyRevenue]);

  const groupedLeads = useMemo(() => pipeline.reduce((accumulator, status) => {
    accumulator[status] = visibleLeads.filter((lead) => lead.status === status);
    return accumulator;
  }, {}), [visibleLeads]);

  const executeAction = useCallback(async (action, successMessage) => {
    setActionBusy(true);
    try {
      await action();
      setSuccess(successMessage);
      await loadDashboard({ background: true, keepFeedback: true });
    } catch (error) {
      setError(error.message);
    } finally {
      setActionBusy(false);
    }
  }, [loadDashboard, setError, setSuccess]);

  const updateLeadStatus = (leadId, status) => executeAction(
    () => patchLead(token, tenantId, leadId, { status }),
    `Lead moved to ${status}.`
  );

  const submitTemplate = async (event) => {
    event.preventDefault();
    await executeAction(async () => {
      await createTemplate(token, tenantId, templateDraft);
      setTemplateDraft({ name: "", message: "" });
    }, "Template saved.");
  };

  const submitBroadcast = async (event) => {
    event.preventDefault();
    await executeAction(async () => {
      await createBroadcast(token, tenantId, {
        ...broadcastDraft,
        target_status: broadcastDraft.target_status || null
      });
      setBroadcastDraft({ name: "Promo Blast", message: "", target_status: "" });
    }, "Broadcast queued.");
  };

  const startBilling = async () => {
    setActionBusy(true);
    try {
      const data = await createCheckout(token, {});
      if (data.url) {
        window.location.href = data.url;
      }
    } catch (error) {
      setError(error.message);
    } finally {
      setActionBusy(false);
    }
  };

  const logout = () => {
    localStorage.removeItem("zline.session");
    setSession(null);
    window.location.href = "/login";
  };

  if (!session) {
    return null;
  }

  if (loading) {
    return (
      <section className="mx-auto max-w-7xl px-6 py-12">
        <div className="rounded-3xl border border-slate-800 bg-slate-900/80 p-10 text-center text-slate-300 shadow-2xl shadow-cyan-950/20">
          Loading your CRM workspace...
        </div>
      </section>
    );
  }

  const templateChars = templateDraft.message.length;
  const broadcastChars = broadcastDraft.message.length;

  return (
    <section className="mx-auto max-w-7xl px-6 py-10">
      <header className="flex flex-col gap-4 rounded-3xl border border-slate-800 bg-slate-900/80 p-6 shadow-2xl shadow-cyan-950/20 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <p className="text-sm uppercase tracking-[0.3em] text-cyan-300">zLine CRM Control Room</p>
          <h1 className="mt-2 text-3xl font-bold text-white">{profile?.tenant_id || tenantId}</h1>
          <p className="mt-2 text-sm text-slate-400">
            Logged in as <span className="font-semibold text-slate-200">{profile?.username}</span> · {profile?.role} · subscription {profile?.subscription_status}
          </p>
          <p className="mt-1 text-xs text-slate-500">Last synced: {formatDateTime(lastSyncAt)}</p>
        </div>
        <div className="flex flex-wrap gap-3">
          <button className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60" onClick={() => loadDashboard({ background: true, keepFeedback: true })} disabled={actionBusy}>
            Refresh data
          </button>
          <button className="rounded-lg border border-cyan-400 px-4 py-2 text-sm font-semibold text-cyan-200 hover:bg-cyan-500/10 disabled:cursor-not-allowed disabled:opacity-60" onClick={startBilling} disabled={actionBusy}>
            Upgrade billing
          </button>
          <button className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 hover:bg-slate-800" onClick={logout}>
            Logout
          </button>
        </div>
      </header>

      {feedback.text ? (
        <div className={`mt-4 flex items-center justify-between gap-4 rounded-xl border px-4 py-3 text-sm ${feedback.tone === "error" ? "border-rose-900 bg-rose-950/40 text-rose-100" : "border-emerald-900 bg-emerald-950/40 text-emerald-100"}`}>
          <span>{feedback.text}</span>
          <button className="text-xs font-semibold opacity-80 hover:opacity-100" onClick={() => setFeedback({ tone: "info", text: "" })} type="button">
            Dismiss
          </button>
        </div>
      ) : null}

      <div className="mt-4 flex flex-wrap items-center gap-3 text-xs text-slate-300">
        <label className="inline-flex items-center gap-2 rounded-lg border border-slate-700 bg-slate-900 px-3 py-2">
          <input type="checkbox" checked={autoRefresh} onChange={(event) => setAutoRefresh(event.target.checked)} />
          Auto refresh every 30s
        </label>
        <span className="rounded-lg border border-slate-700 bg-slate-900 px-3 py-2">Visible leads: {visibleLeads.length}</span>
      </div>

      <div className="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="Total leads" value={stats?.total_leads ?? 0} />
        <MetricCard label="Hot leads" value={stats?.hot_leads ?? 0} />
        <MetricCard label="Revenue" value={formatMoney(stats?.revenue ?? 0)} />
        <MetricCard label="Conversion" value={`${stats?.conversion_rate ?? 0}%`} />
      </div>

      <div className="mt-8 grid gap-6 xl:grid-cols-[1.4fr_0.9fr]">
        <section className="rounded-3xl border border-slate-800 bg-slate-900 p-6">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h2 className="text-xl font-semibold text-white">Lead pipeline</h2>
              <p className="text-sm text-slate-400">Move leads across the funnel and monitor close-ready conversations.</p>
            </div>
            <div className="flex flex-wrap gap-2">
              <input
                className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100"
                value={leadSearch}
                onChange={(event) => setLeadSearch(event.target.value)}
                placeholder="Search lead, phone, note"
              />
              <select
                className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100"
                value={leadSort}
                onChange={(event) => setLeadSort(event.target.value)}
              >
                <option value="updated_desc">Newest update</option>
                <option value="updated_asc">Oldest update</option>
                <option value="score_desc">Highest score</option>
                <option value="score_asc">Lowest score</option>
              </select>
              <select
                className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100"
                value={statusFilter}
                onChange={(event) => setStatusFilter(event.target.value)}
              >
                <option value="all">All statuses</option>
                {pipeline.map((status) => (
                  <option key={status} value={status}>{status}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="mt-6 grid gap-4 lg:grid-cols-5">
            {pipeline.map((status) => (
              <div key={status} className="rounded-2xl border border-slate-800 bg-slate-950/60 p-4">
                <div className="mb-4 flex items-center justify-between">
                  <h3 className="text-sm font-semibold uppercase tracking-[0.2em] text-slate-200">{status}</h3>
                  <span className="rounded-full bg-slate-800 px-2 py-1 text-xs text-slate-300">{groupedLeads[status]?.length || 0}</span>
                </div>
                <div className="space-y-3">
                  {(groupedLeads[status] || []).length ? (groupedLeads[status] || []).map((lead) => (
                    <article key={lead.id} className="rounded-xl border border-slate-800 bg-slate-900 p-3">
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <h4 className="font-semibold text-white">{lead.name || "Unnamed lead"}</h4>
                          <p className="text-xs text-slate-400">{lead.phone || "No phone yet"}</p>
                        </div>
                        <span className="text-xs font-semibold text-cyan-300">Score {lead.score}</span>
                      </div>
                      <p className="mt-2 line-clamp-4 text-xs text-slate-300">{lead.interest || "No notes yet."}</p>
                      <div className="mt-3 flex items-center justify-between text-[11px] text-slate-400">
                        <span>Value {formatMoney(lead.price)}</span>
                        <span>{new Date(lead.updated_at).toLocaleDateString()}</span>
                      </div>
                      <div className="mt-3 grid grid-cols-2 gap-2">
                        {actionsForStatus(lead.status).map((nextStatus) => (
                          <button
                            key={nextStatus}
                            className="rounded-lg border border-slate-700 px-2 py-1 text-xs text-slate-200 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
                            onClick={() => updateLeadStatus(lead.id, nextStatus)}
                            disabled={actionBusy}
                          >
                            Move to {nextStatus}
                          </button>
                        ))}
                      </div>
                    </article>
                  )) : <EmptyState message={`No ${status} leads in this view.`} />}
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="space-y-6">
          <Panel title="Status mix" subtitle="Live lead scoring distribution.">
            <div className="space-y-3">
              {pipeline.map((status) => {
                const count = stats?.status?.[status] || 0;
                const width = `${Math.max(8, ((count || 0) / Math.max(1, stats?.total_leads || 1)) * 100)}%`;
                return (
                  <div key={status}>
                    <div className="mb-1 flex justify-between text-xs text-slate-300">
                      <span>{status}</span>
                      <span>{count}</span>
                    </div>
                    <div className="h-2 rounded-full bg-slate-800">
                      <div className="h-2 rounded-full bg-cyan-400" style={{ width }} />
                    </div>
                  </div>
                );
              })}
            </div>
          </Panel>

          <Panel title="Daily revenue" subtitle="Closed-won revenue over time.">
            <div className="flex h-40 items-end gap-3">
              {dailyRevenue.length ? dailyRevenue.map((point) => (
                <div key={point.date} className="flex flex-1 flex-col items-center gap-2">
                  <div className="flex w-full items-end justify-center rounded-t-lg bg-cyan-500/20 px-2" style={{ height: `${Math.max(12, (point.revenue / revenuePeak) * 120)}px` }}>
                    <span className="pb-2 text-xs font-semibold text-cyan-200">{formatMoney(point.revenue)}</span>
                  </div>
                  <span className="text-[10px] text-slate-400">{point.date}</span>
                </div>
              )) : <p className="text-sm text-slate-400">No closed revenue yet.</p>}
            </div>
          </Panel>
        </section>
      </div>

      <div className="mt-8 grid gap-6 xl:grid-cols-2">
        <Panel title="Message templates" subtitle="Save broadcast scripts and reuse them in one click.">
          <form className="space-y-3" onSubmit={submitTemplate}>
            <input
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
              placeholder="Template name"
              value={templateDraft.name}
              onChange={(event) => setTemplateDraft((current) => ({ ...current, name: event.target.value }))}
              required
            />
            <textarea
              className="min-h-28 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
              placeholder="Template message"
              value={templateDraft.message}
              onChange={(event) => setTemplateDraft((current) => ({ ...current, message: event.target.value }))}
              required
            />
            <div className="flex items-center justify-between text-xs text-slate-400">
              <span>{templateChars} characters</span>
              <span>Reusable in broadcast composer</span>
            </div>
            <button className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950 hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-60" type="submit" disabled={actionBusy}>
              Save template
            </button>
          </form>
          <div className="mt-4 space-y-3">
            {templates.length ? templates.map((template) => (
              <div key={template.id} className="rounded-xl border border-slate-800 bg-slate-950/60 p-4">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <h3 className="font-semibold text-white">{template.name}</h3>
                    <p className="mt-1 text-sm text-slate-300">{template.message}</p>
                  </div>
                  <button
                    className="rounded-lg border border-cyan-500 px-3 py-2 text-xs font-semibold text-cyan-200 hover:bg-cyan-500/10"
                    onClick={() => setBroadcastDraft((current) => ({ ...current, message: template.message, name: template.name }))}
                    type="button"
                  >
                    Use
                  </button>
                </div>
              </div>
            )) : <EmptyState message="No templates yet. Save your best-performing script here." />}
          </div>
        </Panel>

        <Panel title="Broadcast + campaigns" subtitle="Queue async LINE campaigns and monitor replies.">
          <form className="space-y-3" onSubmit={submitBroadcast}>
            <input
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
              placeholder="Campaign name"
              value={broadcastDraft.name}
              onChange={(event) => setBroadcastDraft((current) => ({ ...current, name: event.target.value }))}
              required
            />
            <select
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
              value={broadcastDraft.target_status}
              onChange={(event) => setBroadcastDraft((current) => ({ ...current, target_status: event.target.value }))}
            >
              <option value="">All lead segments</option>
              {pipeline.map((status) => (
                <option key={status} value={status}>{status}</option>
              ))}
            </select>
            <textarea
              className="min-h-28 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
              placeholder="Message to send"
              value={broadcastDraft.message}
              onChange={(event) => setBroadcastDraft((current) => ({ ...current, message: event.target.value }))}
              required
            />
            <div className="text-xs text-slate-400">{broadcastChars} characters</div>
            <button className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950 hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-60" type="submit" disabled={actionBusy}>
              Queue broadcast
            </button>
          </form>
          <div className="mt-4 overflow-hidden rounded-2xl border border-slate-800">
            <table className="min-w-full divide-y divide-slate-800 text-sm">
              <thead className="bg-slate-950/80 text-left text-xs uppercase tracking-[0.2em] text-slate-400">
                <tr>
                  <th className="px-3 py-3">Name</th>
                  <th className="px-3 py-3">Status</th>
                  <th className="px-3 py-3">Sent</th>
                  <th className="px-3 py-3">Replies</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 bg-slate-900/40 text-slate-200">
                {campaigns.length ? campaigns.map((campaign) => (
                  <tr key={campaign.id}>
                    <td className="px-3 py-3">
                      <div className="font-semibold">{campaign.name}</div>
                      <div className="text-xs text-slate-400">{campaign.target_status || "all leads"}</div>
                    </td>
                    <td className="px-3 py-3">
                      <StatusBadge value={campaign.delivery_status} />
                    </td>
                    <td className="px-3 py-3">{campaign.sent_count}</td>
                    <td className="px-3 py-3">{campaign.reply_count} ({campaign.reply_rate}%)</td>
                  </tr>
                )) : (
                  <tr>
                    <td className="px-3 py-6 text-center text-slate-400" colSpan="4">No campaigns yet.</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </Panel>
      </div>
    </section>
  );
}

function MetricCard({ label, value }) {
  return (
    <article className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
      <p className="text-sm text-slate-400">{label}</p>
      <h2 className="mt-3 text-3xl font-bold text-white">{value}</h2>
    </article>
  );
}

function Panel({ title, subtitle, children }) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900 p-6">
      <div className="mb-4">
        <h2 className="text-xl font-semibold text-white">{title}</h2>
        <p className="mt-1 text-sm text-slate-400">{subtitle}</p>
      </div>
      {children}
    </section>
  );
}

function EmptyState({ message }) {
  return (
    <div className="rounded-xl border border-dashed border-slate-700 bg-slate-900/30 px-3 py-4 text-center text-xs text-slate-400">
      {message}
    </div>
  );
}

function StatusBadge({ value }) {
  const style = value === "sent"
    ? "border-emerald-700 bg-emerald-950/40 text-emerald-100"
    : value === "failed"
      ? "border-rose-700 bg-rose-950/40 text-rose-100"
      : "border-amber-700 bg-amber-950/40 text-amber-100";

  return <span className={`inline-flex rounded-full border px-2 py-1 text-xs ${style}`}>{value || "queued"}</span>;
}
