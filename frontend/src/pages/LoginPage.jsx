import React, { useMemo, useState } from "react";
import AuthForm from "../components/AuthForm";
import { postLogin } from "../lib/api";

export default function LoginPage() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const initialUsername = useMemo(() => new URLSearchParams(window.location.search).get("username") || "", []);

  const submitLogin = async (payload) => {
    setLoading(true);
    try {
      const data = await postLogin(payload);
      localStorage.setItem("zline.session", JSON.stringify(data));
      setResult(data);
      window.location.href = "/dashboard";
    } catch (error) {
      setResult({ error: error.message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="px-6 py-16">
      <AuthForm mode="login" onSubmit={submitLogin} loading={loading} result={result} initialUsername={initialUsername} />
      <p className="mt-6 text-center text-sm text-slate-400">
        New here? <a className="font-semibold text-cyan-300" href="/signup">Create an account</a>
      </p>
    </section>
  );
}
