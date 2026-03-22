export default function CTAButton({ onClick, children, className = "" }) {
  return (
    <button
      onClick={onClick}
      className={`rounded-lg px-6 py-3 text-base font-bold transition ${className}`}
    >
      {children}
    </button>
  );
}
