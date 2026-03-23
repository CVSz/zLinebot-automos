import React from "react";

const features = [
  "FastAPI backend + worker + Kafka + Redis + Postgres",
  "React + Tailwind frontend",
  "NGINX reverse proxy + TLS",
  "Backup and health monitoring scripts",
  "Admin/User/DevOps static control panels"
];

export default function Features() {
  return (
    <section className="mx-auto max-w-4xl px-6 py-14">
      <h2 className="mb-6 text-center text-3xl font-bold">Features</h2>
      <ul className="list-disc space-y-2 pl-6">
        {features.map((feature) => (
          <li key={feature}>{feature}</li>
        ))}
      </ul>
    </section>
  );
}
