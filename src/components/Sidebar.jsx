// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Sidebar navigation (Tailwind)
// ─────────────────────────────────────────────────────────────
// Single source of truth for admin nav. Deep forest-green shell (#1b3b22
// per municipal theme) with white text. Active route is derived from
// react-router's NavLink (isActive).
//
// Exact menu structure (municipal console):
//   Overview, Users, Verifications, Listings, Exchanges, Time Bank,
//   Notifications, Content, Reports, Analytics, Audit Logs, Settings
// plus a bottom "Sign out" button.
// ─────────────────────────────────────────────────────────────
import { NavLink } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import logo from "../assets/logo.jpg";
import { COMMUNITY } from "../config/community";

// Flat menu matching the municipal console structure. `end: true` marks
// exact-match routes (so /admin stays inactive on sub-pages).
const NAV = [
  { to: "/admin", label: "Overview", icon: "📊", end: true },
  { to: "/admin/users", label: "Users", icon: "👥" },
  { to: "/admin/verification", label: "Verifications", icon: "✅" },
  { to: "/admin/listings", label: "Listings", icon: "📦", end: true },
  { to: "/admin/exchanges", label: "Exchanges", icon: "🔄" },
  { to: "/admin/timebank", label: "Time Bank", icon: "⏱️" },
  { to: "/admin/notifications", label: "Notifications", icon: "🔔" },
  { to: "/admin/content", label: "Content", icon: "📄" },
  { to: "/admin/reports", label: "Reports", icon: "🚩" },
  { to: "/admin/analytics", label: "Analytics", icon: "📈" },
  { to: "/admin/audit-logs", label: "Audit Logs", icon: "📋" },
  { to: "/admin/settings", label: "Settings", icon: "⚙️" },
];

const linkClass = ({ isActive }) =>
  `flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition ${
    isActive
      ? "bg-white/15 font-semibold text-white shadow-[inset_3px_0_0_#4ade80]"
      : "text-white/75 hover:translate-x-0.5 hover:bg-white/10 hover:text-white"
  }`;

export default function Sidebar() {
  const { logout } = useAuth();

  return (
    <aside className="flex w-64 shrink-0 flex-col bg-[#1b3b22] text-white">
      <div className="flex items-center gap-3 border-b border-white/10 px-5 py-5">
        <img src={logo} alt="CBLREP logo" className="h-10 w-10 rounded-full object-cover" />
        <div>
          <p className="text-sm font-extrabold tracking-wide">CBLREP ADMIN</p>
          <p className="text-xs text-white/60">{COMMUNITY.shortLabel}</p>
        </div>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {NAV.map((item) => (
          <NavLink key={item.to} to={item.to} end={item.end} className={linkClass}>
            <span aria-hidden>{item.icon}</span>
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-white/10 p-3">
        <div className="mb-2 rounded-lg border border-white/10 bg-black/20 px-3 py-2">
          <p className="text-[10px] font-bold uppercase tracking-[0.15em] text-white/50">
            Community
          </p>
          <p className="mt-0.5 text-xs font-semibold text-white">{COMMUNITY.label}</p>
        </div>
        <button
          type="button"
          onClick={logout}
          className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-semibold text-white/85 transition hover:bg-red-500/20 hover:text-white"
        >
          <span aria-hidden>🚪</span>
          <span>Sign out</span>
        </button>
      </div>
    </aside>
  );
}
