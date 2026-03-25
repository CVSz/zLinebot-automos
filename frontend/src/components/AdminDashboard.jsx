export default function AdminDashboard({ users = [] }) {
  return (
    <div className="rounded-lg border border-slate-700 bg-slate-900 p-4 text-slate-100">
      <h1 className="mb-4 text-xl font-bold">🛠 Admin Panel</h1>
      <div className="space-y-2">
        {users.map((u) => (
          <div key={u.id} className="rounded border border-slate-700 p-2">
            {u.email} - {u.plan}
          </div>
        ))}
      </div>
    </div>
  );
}
