const items = [
  {
    title: "Live Demo API",
    detail: "แชตทดสอบได้ทันทีผ่าน /api/chat เพื่อโชว์คุณค่าให้ลูกค้าก่อนซื้อ",
  },
  {
    title: "Auto Money Funnel",
    detail: "Free Trial → Stripe Checkout → Paid Plan → Upsell ใน flow เดียว",
  },
  {
    title: "Viral Content Ready",
    detail: "มี template สำหรับ TikTok / Shorts / Reels พร้อม hook ที่หยิบใช้ได้ทันที",
  },
];

export default function Features() {
  return (
    <section className="mt-8 grid gap-4 md:grid-cols-3">
      {items.map((item) => (
        <article
          key={item.title}
          className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6"
        >
          <h3 className="text-lg font-semibold text-white">{item.title}</h3>
          <p className="mt-2 text-sm leading-relaxed text-slate-300">{item.detail}</p>
        </article>
      ))}
    </section>
  );
}
