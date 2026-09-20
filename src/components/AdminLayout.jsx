// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Admin layout shell (Tailwind)
// ─────────────────────────────────────────────────────────────
// Wraps every /admin/* page: fixed sidebar + scrollable content column
// with the header (profile/logout) on top. A global toast slot surfaces
// success/error feedback from page actions (see pages/*).
// ─────────────────────────────────────────────────────────────
import Sidebar from "./Sidebar";
import Header from "./Header";

export default function AdminLayout({ title, toast, children }) {
  return (
    <div className="flex min-h-screen bg-stone-100 text-stone-800">
      <Sidebar />
      <main className="min-w-0 flex-1 px-6 py-6 lg:px-10">
        <Header title={title} />
        {toast ? (
          <div
            role="status"
            className="mb-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2.5 text-sm font-medium text-emerald-900"
          >
            {toast}
          </div>
        ) : null}
        <div className="space-y-5">{children}</div>
      </main>
    </div>
  );
}
