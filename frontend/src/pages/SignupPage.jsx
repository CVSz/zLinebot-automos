import React, { useState } from "react";
import AuthForm from "../components/AuthForm";
import { postRegister } from "../lib/api";

export default function SignupPage() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [createdUsername, setCreatedUsername] = useState("");

  const submitSignup = async (payload) => {
    setLoading(true);
    try {
      const data = await postRegister(payload);
      setCreatedUsername(payload.username);
      setResult(data);
    } catch (error) {
      setResult({ error: error.message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="px-6 py-16">
      <AuthForm mode="signup" onSubmit={submitSignup} loading={loading} result={result} />
      <p className="mt-6 text-center text-sm text-slate-400">
        Already have a workspace? <a className="font-semibold text-cyan-300" href="/login">Login here</a>
      </p>
      {result?.ok ? (
        <div className="mx-auto mt-4 max-w-md rounded-2xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-4 text-sm text-emerald-100">
          <p className="font-semibold">Next step</p>
          <p className="mt-1">Your workspace is ready. Sign in to open the dashboard and start managing leads.</p>
          <a className="mt-4 inline-flex rounded-lg bg-emerald-400 px-4 py-2 font-semibold text-slate-950" href={`/login${createdUsername ? `?username=${encodeURIComponent(createdUsername)}` : ""}`}>
            Continue to login
          </a>
        </div>
      ) : null}
    </section>
  );
}
