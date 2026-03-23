import React from "react";

const items = [
  "React + Tailwind landing and conversion templates",
  "Signup/Login forms wired to /api/register and /api/login",
  "Demo chat widget wired to /api/chat",
  "NGINX TLS reverse proxy for /api, /admin, /user, /devops",
  "Docker Compose stack: api, worker, db, redis, zookeeper, kafka, nginx"
];

export default function Features() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-8">
      <h2 className="text-3xl font-bold text-white">What you get out of the box</h2>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        {items.map((item) => (
          <article key={item} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 text-slate-200 shadow-lg shadow-black/20">
            {item}
          </article>
        ))}
      </div>
    </section>
  );
}
