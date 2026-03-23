import React, { useState } from "react";
import { postChat } from "../lib/api";

export default function ChatDemo() {
  const [message, setMessage] = useState("Generate launch copy for my webinar.");
  const [reply, setReply] = useState("");
  const [loading, setLoading] = useState(false);

  const onAsk = async (event) => {
    event.preventDefault();
    setLoading(true);
    try {
      const data = await postChat({ message });
      setReply(data.reply ?? "No reply");
    } catch (error) {
      setReply(error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="mx-auto max-w-6xl px-6 py-10">
      <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
        <h3 className="text-2xl font-bold text-white">Chat endpoint demo</h3>
        <form className="mt-4 flex flex-col gap-3 md:flex-row" onSubmit={onAsk}>
          <input
            className="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100 outline-none focus:border-cyan-300"
            value={message}
            onChange={(event) => setMessage(event.target.value)}
          />
          <button className="rounded-lg bg-cyan-500 px-5 py-2 font-semibold text-slate-900 hover:bg-cyan-400" type="submit">
            {loading ? "Sending..." : "Send"}
          </button>
        </form>
        <p className="mt-4 text-sm text-slate-200">Response: {reply || "(waiting)"}</p>
      </div>
    </section>
  );
}
