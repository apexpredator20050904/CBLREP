// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Admin layout shell (Tailwind)
// ─────────────────────────────────────────────────────────────
// Wraps every /admin/* page: a FIXED sidebar and a FIXED top strip
// (header + compact mobile nav). Only the page content scrolls — inside
// <main> — never the document. The nav's own link list scrolls internally
// when it does not fit the viewport. A global toast slot surfaces
// success/error feedback from page actions (see pages/*).
// ─────────────────────────────────────────────────────────────
import Sidebar from "./Sidebar";
import { NAV } from "./navItems";
import Header from "./Header";
import { NavLink } from "react-router-dom";

export default function AdminLayout({ title, toast, children }) {
  return (
    <div className="flex h-dvh overflow-hidden bg-[#f8fafc] text-stone-800">
      <Sidebar />
      {/* md:pl-56 offsets the fixed (out-of-flow) sidebar. */}
      <div className="flex min-w-0 flex-1 flex-col md:pl-56">
        {/* Pinned top strip — header + compact nav for small screens. */}
        <div className="app-chrome shrink-0 border-b border-stone-200 bg-[#f8fafc] px-4 py-3 sm:px-6 lg:px-10">
          <Header title={title} />
          {/* Compact horizontal nav keeps core actions reachable on small screens. */}
          <nav className="mt-3 flex gap-1.5 overflow-x-auto pb-1 md:hidden">
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
        </div>
        {/* The only scrolling region on the page. */}
        <main className="min-w-0 flex-1 overflow-y-auto px-4 py-4 sm:px-6 md:py-6 lg:px-10">
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
    </div>
  );
}
