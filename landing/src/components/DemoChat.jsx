import { useState } from "react";

export default function DemoChat() {
  const [msg, setMsg] = useState("");
  const [reply, setReply] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const sendMsg = async () => {
    setLoading(true);
    setError("");

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer DEMO_TOKEN",
        },
        body: JSON.stringify({ message: msg }),
      });

      if (!res.ok) {
        throw new Error(`Request failed with status ${res.status}`);
      }

      const data = await res.json();
      setReply(data.reply || "ไม่มีข้อความตอบกลับ");
    } catch (err) {
      setError("ส่งข้อความไม่สำเร็จ ลองใหม่อีกครั้ง");
      setReply("");
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <section id="demo" className="mt-8 rounded-2xl border border-slate-800 bg-white p-6">
      <h2 className="text-xl font-semibold text-slate-900">Live Demo Chat</h2>
      <p className="mt-1 text-sm text-slate-600">ลองพิมพ์คำถามเพื่อทดสอบคุณภาพ AI ก่อนอัปเกรด</p>

      <textarea
        className="mt-4 w-full rounded-lg border border-slate-300 p-3"
        value={msg}
        onChange={(e) => setMsg(e.target.value)}
        placeholder="ลองพิมพ์ข้อความ"
      />

      <button
        className="mt-3 rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white disabled:opacity-60"
        onClick={sendMsg}
        disabled={loading || !msg.trim()}
      >
        {loading ? "กำลังส่ง..." : "ส่งข้อความ"}
      </button>

      {error && <div className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      {reply && <div className="mt-4 rounded-lg bg-slate-100 p-4 text-slate-900">{reply}</div>}
    </section>
  );
}
