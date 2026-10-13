// Flat menu matching the municipal console structure. `end: true` marks
// exact-match routes (so /admin stays inactive on sub-pages).
export const NAV = [
  { to: "/admin", label: "Overview", icon: "📊", end: true },
  { to: "/admin/users", label: "Users", icon: "👥" },
  { to: "/admin/verification", label: "Verifications", icon: "✅" },
  { to: "/admin/listings", label: "Listings", icon: "📦", end: true },
  { to: "/admin/inquiries", label: "Inquiries", icon: "💬" },
  { to: "/admin/map", label: "Map", icon: "🗺️" },
  { to: "/admin/exchanges", label: "Exchanges", icon: "🔄" },
  { to: "/admin/notifications", label: "Notifications", icon: "🔔" },
  { to: "/admin/content", label: "Content", icon: "📄" },
  { to: "/admin/reports", label: "Reports", icon: "🚩" },
  { to: "/admin/analytics", label: "Analytics", icon: "📈" },
  { to: "/admin/audit-logs", label: "Audit Logs", icon: "📋" },
  { to: "/admin/settings", label: "Settings", icon: "⚙️" },
];
