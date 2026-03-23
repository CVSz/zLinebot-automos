import React, { useState } from "react";

export default function AuthForm({ mode, onSubmit, loading, result }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [tenantName, setTenantName] = useState("");

  const actionLabel = mode === "signup" ? "Create workspace" : "Sign in";

  const handleSubmit = async (event) => {
    event.preventDefault();
    await onSubmit({ username, password, tenant_name: tenantName || undefined });
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
          />
        </label>
      </div>
      <button
        className="mt-5 w-full rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-900 hover:bg-cyan-400 disabled:opacity-60"
        type="submit"
        disabled={loading}
      >
        {loading ? "Please wait..." : actionLabel}
      </button>
      {result ? (
        <pre className="mt-4 overflow-x-auto rounded-lg bg-slate-950 p-3 text-xs text-cyan-200">{JSON.stringify(result, null, 2)}</pre>
      ) : null}
    </form>
  );
}
