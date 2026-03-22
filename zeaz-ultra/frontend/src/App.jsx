import Hero from "./components/Hero";
import Features from "./components/Features";
import DemoChat from "./components/DemoChat";

export default function App() {
  const startCheckout = async () => {
    const res = await fetch("/api/create-checkout", { method: "POST" });
    const data = await res.json();
    if (data.url) {
      window.location.href = data.url;
    }
  };

  const scrollToDemo = () => {
    document.getElementById("demo")?.scrollIntoView({ behavior: "smooth" });
  };

  return (
    <div className="min-h-screen bg-slate-950 px-4 py-8 text-white md:px-8">
      <main className="mx-auto max-w-6xl">
        <Hero onUpgrade={startCheckout} onFreeTrial={scrollToDemo} />
        <Features />
        <DemoChat />
      </main>
    </div>
  );
}
