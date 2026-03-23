import React from "react";

export default function Hero() {
  return (
    <section className="bg-blue-600 px-6 py-16 text-center text-white">
      <h1 className="text-4xl font-bold md:text-5xl">ZEAZ Ultra SaaS Pack</h1>
      <p className="mx-auto mt-4 max-w-2xl text-lg md:text-xl">
        Deploy full SaaS stack with AI, Kafka, Redis, and Postgres in minutes.
      </p>
      <a href="/user/" className="mt-6 inline-block rounded-lg bg-white px-6 py-3 font-semibold text-blue-600">
        Get Started
      </a>
    </section>
  );
}
