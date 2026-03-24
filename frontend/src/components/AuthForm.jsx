import React, { useMemo, useState } from "react";

function messageFromResult(result) {
  if (!result) {
    return null;
  }

  if (result.error) {
    return { tone: "error", text: result.error };
  }

  if (result.ok && result.tenant?.name) {
    return { tone: "success", text: `Workspace ${result.tenant.name} is ready.` };
  }

  if (result.user?.username) {
    return { tone: "success", text: `Signed in as ${result.user.username}. Redirecting...` };
  }

  return null;
}

export default function AuthForm({ mode, onSubmit, loading, result, initialUsername = "" }) {
  const [username, setUsername] = useState(initialUsername);
  const [password, setPassword] = useState("");
  const [tenantName, setTenantName] = useState("");

  const actionLabel = mode === "signup" ? "Create workspace" : "Sign in";
  const statusMessage = useMemo(() => messageFromResult(result), [result]);

  const handleSubmit = async (event) => {
    event.preventDefault();
    await onSubmit({
      username: username.trim(),
      password,
      tenant_name: tenantName.trim() || undefined
    });
  };

  return (
    <form className="mx-auto mt-6 w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-6" onSubmit={handleSubmit}>
      <h1 className="text-2xl font-bold text-white">{mode === "signup" ? "Create your CRM workspace" : "Welcome back"}</h1>
      <div className="mt-4 space-y-4">
        {mode === "signup" ? (
          <label className="block">
            <span className="mb-2 block text-sm text-slate-300">Workspace name</span>
            <input
              className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100 outline-none focus:border-cyan-300"
              value={tenantName}
              onChange={(event) => setTenantName(event.target.value)}
              placeholder="Sea Commerce"
              minLength={3}
              autoComplete="organization"
            />
          </label>
        ) : null}
        <label className="block">
          <span className="mb-2 block text-sm text-slate-300">Username</span>
          <input
            className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100 outline-none focus:border-cyan-300"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            placeholder="yourname"
            required
            minLength={3}
            autoComplete="username"
            pattern="[A-Za-z0-9_.-]+"
            title="Use letters, numbers, dots, dashes, or underscores."
          />
        </label>
        <label className="block">
          <span className="mb-2 block text-sm text-slate-300">Password</span>
          <input
            type="password"
            className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100 outline-none focus:border-cyan-300"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder="********"
            required
            minLength={8}
            autoComplete={mode === "signup" ? "new-password" : "current-password"}
          />
        </label>
      </div>
      <button
        className="mt-5 w-full rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-900 hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-60"
        type="submit"
        disabled={loading}
      >
        {loading ? "Please wait..." : actionLabel}
      </button>
      {statusMessage ? (
        <div
          className={`mt-4 rounded-lg border px-3 py-3 text-sm ${statusMessage.tone === "error" ? "border-rose-500/40 bg-rose-500/10 text-rose-100" : "border-emerald-500/40 bg-emerald-500/10 text-emerald-100"}`}
        >
          {statusMessage.text}
        </div>
      ) : null}
      {mode === "signup" ? (
        <p className="mt-3 text-xs text-slate-400">
          Usernames must be at least 3 characters and may contain letters, numbers, dots, dashes, or underscores.
        </p>
      ) : null}
    </form>
  );
}
