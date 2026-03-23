import React from "react";

export default function CTA() {
  return (
    <section className="bg-slate-100 px-6 py-14 text-center">
      <h3 className="text-2xl font-bold">Start your SaaS now</h3>
      <p className="mx-auto mt-3 max-w-2xl">Create an account and launch your dashboard in one click.</p>
      <a href="/user/" className="mt-6 inline-block rounded-lg bg-blue-600 px-6 py-3 font-semibold text-white">
        Launch Dashboard
      </a>
    </section>
  );
}
