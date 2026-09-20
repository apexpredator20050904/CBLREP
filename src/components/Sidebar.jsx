// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Sidebar navigation (Tailwind)
// ─────────────────────────────────────────────────────────────
// Single source of truth for admin nav. Groups mirror the municipal
// workflow: resident verification → listing moderation → reporting.
// Active route is derived from react-router's NavLink (isActive).
// ─────────────────────────────────────────────────────────────
import { NavLink } from "react-router-dom";
import logo from "../assets/logo.jpg";
import { COMMUNITY } from "../config/community";

const NAV = [
  { to: "/admin", label: "Dashboard", icon: "🛡️", end: true },
  {
    group: "Residents",
    items: [
      { to: "/admin/verification", label: "Verification", icon: "✅" },
      { to: "/admin/users", label: "All Users", icon: "👥" },
    ],
  },
  {
    group: "Moderation",
    items: [
      { to: "/admin/listings", label: "All Listings", icon: "📦" },
      { to: "/admin/listings/offers", label: "Offers", icon: "🎁" },
      { to: "/admin/listings/needs", label: "Needs", icon: "🙏" },
      { to: "/admin/listings/flagged", label: "Flagged", icon: "🚩" },
    ],
  },
  { to: "/admin/analytics", label: "Analytics & Reports", icon: "📈" },
  { to: "/admin/audit-logs", label: "Audit Logs", icon: "📋" },
];

const linkClass = ({ isActive }) =>
  `flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition ${
    isActive
      ? "bg-white/15 font-semibold text-white shadow-[inset_3px_0_0_#d97706]"
      : "text-emerald-50/80 hover:translate-x-0.5 hover:bg-white/10 hover:text-white"
  }`;

export default function Sidebar() {
  return (
    <aside className="flex w-64 shrink-0 flex-col bg-emerald-950 text-white">
      <div className="flex items-center gap-3 border-b border-white/10 px-5 py-5">
        <img src={logo} alt="CBLREP logo" className="h-10 w-10 rounded-full object-cover" />
        <div>
          <p className="text-sm font-extrabold tracking-wide">CBLREP ADMIN</p>
          <p className="text-xs text-emerald-200/70">{COMMUNITY.shortLabel}</p>
        </div>
      </div>

      <nav className="flex-1 space-y-4 overflow-y-auto px-3 py-4">
        {NAV.map((entry) =>
          entry.group ? (
            <div key={entry.group} className="space-y-1">
              <p className="px-3 text-[10px] font-bold uppercase tracking-[0.15em] text-emerald-200/60">
                {entry.group}
              </p>
              {entry.items.map((item) => (
                <NavLink key={item.to} to={item.to} end className={linkClass}>
                  <span aria-hidden>{item.icon}</span>
                  <span>{item.label}</span>
                </NavLink>
              ))}
            </div>
          ) : (
            <NavLink key={entry.to} to={entry.to} end={entry.end} className={linkClass}>
              <span aria-hidden>{entry.icon}</span>
              <span>{entry.label}</span>
            </NavLink>
          )
        )}
      </nav>

      <div className="border-t border-white/10 p-4">
        <div className="rounded-lg border border-white/10 bg-black/20 p-3">
          <p className="text-[10px] font-bold uppercase tracking-[0.15em] text-emerald-200/60">
            Community
          </p>
          <p className="mt-1 text-xs font-semibold text-white">{COMMUNITY.label}</p>
        </div>
      </div>
    </aside>
  );
}
