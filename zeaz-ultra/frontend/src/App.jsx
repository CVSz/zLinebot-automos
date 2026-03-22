import { useState } from "react";
import axios from "axios";

const PRICE_ID = "price_basic_9usd";

export default function App() {
  const [msg, setMsg] = useState("");
  const [res, setRes] = useState("");
  const [sending, setSending] = useState(false);
  const [registering, setRegistering] = useState(false);
  const [toast, setToast] = useState("");

  const startFreeTrial = async () => {
    setRegistering(true);
    setToast("");
    try {
      const r = await axios.post("/api/register");
      localStorage.token = r.data.token;
      setToast(r.data.message);
    } catch {
      setToast("สมัครไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    } finally {
      setRegistering(false);
    }
  };

  const send = async () => {
    setSending(true);
    try {
      const r = await axios.post(
        "/api/chat",
        { message: msg },
        {
          headers: { Authorization: "Bearer " + localStorage.token },
        }
      );
      setRes(r.data.reply);
    } catch (error) {
      const detail = error?.response?.data?.detail;
      setRes(detail || "ส่งข้อความไม่สำเร็จ กรุณาสมัคร Free Trial ก่อน");
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <main className="mx-auto max-w-5xl p-8 md:p-12">
        <section className="rounded-2xl border border-slate-800 bg-slate-900/60 p-8 shadow-2xl">
          <p className="inline-block rounded-full border border-emerald-400/30 bg-emerald-400/10 px-3 py-1 text-xs font-semibold text-emerald-300">
            AI SaaS พร้อมขายทันที
          </p>
          <h1 className="mt-4 text-3xl font-bold leading-tight md:text-5xl">
            ทำเงินด้วย AI ใน 10 นาที
          </h1>
          <h2 className="mt-2 text-xl font-semibold text-blue-300 md:text-2xl">
            ระบบ SaaS อัจฉริยะ ทำงานแทนคุณได้ 24/7
          </h2>
          <p className="mt-4 max-w-2xl text-slate-300">
            สมัครฟรี → ใช้ AI Tool → อัปเกรดเพียง $9/เดือน
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <button
              onClick={startFreeTrial}
              disabled={registering}
              className="rounded-lg border border-slate-600 px-5 py-3 font-semibold transition hover:border-slate-400 disabled:cursor-not-allowed disabled:opacity-70"
            >
              {registering ? "กำลังสมัคร..." : "Free Trial"}
            </button>
            <button
              onClick={() =>
                (window.location.href = `/api/checkout?price_id=${PRICE_ID}`)
              }
              className="rounded-lg bg-emerald-500 px-5 py-3 font-semibold text-slate-950 transition hover:bg-emerald-400"
            >
              Upgrade Paid
            </button>
          </div>
          {toast ? <p className="mt-4 text-sm text-emerald-300">{toast}</p> : null}
        </section>

        <section className="mt-8 grid gap-4 md:grid-cols-3">
          {[
            { title: "Landing", value: "React + Tailwind" },
            { title: "Payment", value: "Stripe Checkout" },
            { title: "Funnel", value: "Free → Paid → Upsell" },
          ].map((item) => (
            <div
              key={item.title}
              className="rounded-xl border border-slate-800 bg-slate-900 p-5"
            >
              <div className="text-sm text-slate-400">{item.title}</div>
              <div className="mt-2 text-lg font-semibold">{item.value}</div>
            </div>
          ))}
        </section>

        <section
          id="chat-demo"
          className="mt-8 rounded-2xl border border-slate-800 bg-slate-900 p-6"
        >
          <h2 className="text-xl font-semibold">Live Demo: AI Chat</h2>
          <p className="mt-2 text-sm text-slate-300">
            ลองส่งข้อความผ่าน /api/chat เพื่อทดสอบคุณภาพก่อนตัดสินใจอัปเกรด
          </p>
          <div className="mt-4 flex flex-col gap-3 md:flex-row">
            <input
              value={msg}
              onChange={(e) => setMsg(e.target.value)}
              placeholder="พิมพ์สิ่งที่อยากให้ AI ช่วย..."
              className="w-full rounded-lg border border-slate-700 bg-slate-950 p-3 text-slate-100"
            />
            <button
              onClick={send}
              disabled={sending || !msg.trim()}
              className="rounded-lg bg-blue-500 px-6 py-3 font-semibold text-white transition hover:bg-blue-400 disabled:cursor-not-allowed disabled:bg-blue-700"
            >
              {sending ? "Sending..." : "Send"}
            </button>
          </div>
          <div className="mt-4 min-h-20 rounded-lg border border-slate-800 bg-slate-950/80 p-4 text-slate-200">
            {res || "ผลลัพธ์จาก AI จะแสดงที่นี่"}
          </div>
        </section>

        <section className="mt-8 grid gap-4 md:grid-cols-2">
          <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
            <h3 className="text-lg font-semibold">Testimonials</h3>
            <blockquote className="mt-3 border-l-2 border-emerald-500 pl-4 text-slate-300">
              “ลองแล้ว ได้ผลจริง!”
            </blockquote>
          </div>
          <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
            <h3 className="text-lg font-semibold">Trust Signals</h3>
            <ul className="mt-3 space-y-2 text-slate-300">
              <li>SSL ✅</li>
              <li>ใช้ Stripe จ่ายเงินปลอดภัย ✅</li>
            </ul>
          </div>
        </section>
      </main>
    </div>
  );
}
