// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Admin layout shell (Tailwind)
// ─────────────────────────────────────────────────────────────
// Wraps every /admin/* page: fixed sidebar + scrollable content column
// with the header (profile/logout) on top. A global toast slot surfaces
// success/error feedback from page actions (see pages/*).
// ─────────────────────────────────────────────────────────────
import Sidebar from "./Sidebar";
import { NAV } from "./navItems";
import Header from "./Header";
import { NavLink } from "react-router-dom";

export default function AdminLayout({ title, toast, children }) {
  return (
    <div className="flex min-h-screen bg-[#f8fafc] text-stone-800">
      <Sidebar />
      <main className="min-w-0 flex-1 px-4 py-4 sm:px-6 md:py-6 lg:px-10">
        <Header title={title} />
        {/* Compact horizontal nav keeps core actions reachable on small screens. */}
        <nav className="-mx-4 mb-4 flex gap-1.5 overflow-x-auto px-4 pb-1 md:hidden">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `whitespace-nowrap rounded-full px-3 py-1.5 text-xs font-semibold ${
                  isActive ? "bg-emerald-800 text-white" : "bg-white text-stone-600 border border-stone-200"
                }`
              }
            >
              {item.icon} {item.label}
            </NavLink>
          ))}
        </nav>
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
