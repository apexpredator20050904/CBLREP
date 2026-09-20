// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Dashboard overview (/admin)
// ─────────────────────────────────────────────────────────────
// Landing page after login. Summary stat cards (GET /admin/dashboard) +
// recent system activity + community health snapshot. Cards are read-only;
// moderation happens in the Verification / Listings modules.
// ─────────────────────────────────────────────────────────────
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import AdminLayout from "../components/AdminLayout";
import { StatCard } from "../components/ui";
import { fetchDashboardStats } from "../services/adminApi";

const CARDS = [
  ["totalUsers", "Total Users", "👥"],
  ["verifiedUsersCount", "Verified Users", "✅"],
  ["pendingVerificationCount", "Pending Verifications", "⏳"],
  ["activeListings", "Active Resources", "📦"],
  ["openFlaggedContent", "Flagged Resources", "🚩"],
  ["totalExchanges", "Total Exchanges", "🔄"],
];

export default function DashboardPage() {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    fetchDashboardStats().then(setData).catch((e) => setError(e.message));
  }, []);

  return (
    <AdminLayout title="Admin Dashboard">
      {error ? (
        <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">
          Failed to load dashboard: {error}
        </p>
      ) : !data ? (
        <p className="text-sm text-stone-500">Loading live database statistics…</p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {CARDS.map(([key, label, icon]) => (
              <StatCard key={key} icon={icon} label={label} value={data[key]} />
            ))}
          </div>

          <div className="grid gap-5 lg:grid-cols-3">
            <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm lg:col-span-2">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="font-bold text-emerald-950">Recent System Activity</h2>
                <Link to="/admin/audit-logs" className="text-sm font-semibold text-emerald-700 hover:underline">
                  View audit logs →
                </Link>
              </div>
              {(data.recentActions || []).length === 0 ? (
                <p className="py-6 text-center text-sm text-stone-500">
                  No recent activity recorded yet.
                </p>
              ) : (
                <ul className="divide-y divide-stone-100">
                  {data.recentActions.map((a, i) => (
                    <li key={i} className="flex items-start justify-between gap-4 py-3">
                      <div>
                        <p className="font-semibold text-emerald-950">{a.title}</p>
                        <p className="text-sm text-stone-500">{a.description}</p>
                      </div>
                      <span className="whitespace-nowrap text-xs text-stone-400">{a.time}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
              <h2 className="mb-3 font-bold text-emerald-950">Community Health</h2>
              <dl className="divide-y divide-stone-100 text-sm">
                {[
                  ["Verification rate", data.verifiedUsersPercent],
                  ["Pending verification", data.pendingVerificationPercent],
                  ["Listings awaiting review", data.pendingReviewListings ?? 0],
                  ["Exchanges this month", data.exchangesThisMonth ?? 0],
                ].map(([label, value]) => (
                  <div key={label} className="flex items-center justify-between py-2.5">
                    <dt className="text-stone-500">{label}</dt>
                    <dd className="font-bold tabular-nums text-emerald-950">{value}</dd>
                  </div>
                ))}
              </dl>
            </div>
          </div>
        </>
      )}
    </AdminLayout>
  );
}
