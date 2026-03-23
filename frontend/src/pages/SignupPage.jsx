import React, { useState } from "react";
import AuthForm from "../components/AuthForm";
import { postRegister } from "../lib/api";

export default function SignupPage() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);

  const submitSignup = async (payload) => {
    setLoading(true);
    try {
      const data = await postRegister(payload);
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
    </section>
  );
}
