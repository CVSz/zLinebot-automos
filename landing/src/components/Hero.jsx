import CTAButton from "./CTAButton";

export default function Hero({ onUpgrade, onFreeTrial }) {
  return (
    <section className="rounded-3xl bg-gradient-to-r from-blue-400 to-purple-600 px-6 py-20 text-center text-white shadow-2xl md:px-12">
      <p className="mx-auto inline-block rounded-full bg-white/20 px-4 py-1 text-sm font-semibold">
        Full Ultra Pack พร้อมใช้งาน
      </p>
      <h1 className="mt-6 text-4xl font-bold leading-tight md:text-5xl">
        ทำเงินด้วย AI ใน 10 นาที
      </h1>
      <p className="mx-auto mt-4 max-w-2xl text-lg md:text-xl">
        สมัครฟรี → ใช้ AI Tool → อัปเกรดเพียง $9/เดือน พร้อมระบบจ่ายเงินอัตโนมัติ
      </p>
      <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
        <CTAButton
          onClick={onUpgrade}
          className="bg-white text-blue-700 hover:bg-blue-50"
        >
          อัปเกรดเลย
        </CTAButton>
        <CTAButton
          onClick={onFreeTrial}
          className="border border-white/70 bg-transparent text-white hover:bg-white/10"
        >
          ทดลองฟรี
        </CTAButton>
      </div>
    </section>
  );
}
