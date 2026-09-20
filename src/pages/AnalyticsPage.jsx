// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Analytics & reporting (/admin/analytics)
// Summary cards + per-barangay breakdowns (GET /admin/analytics),
// with CSV download and print-to-PDF export of the municipal log.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { StatCard, btnGhost, btnPrimary, dateInputClass } from "../components/ui";
import {
  downloadAnalyticsCSV,
  fetchAnalytics,
  openAnalyticsPDF,
} from "../services/adminApi";

export default function AnalyticsPage() {
  const [data, setData] = useState(null);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [toast, setToast] = useState("");

  const load = useCallback(async () => {
    try {
      setData(await fetchAnalytics({ from: from || undefined, to: to || undefined }));
    } catch (e) {
      setToast(e.message);
      setTimeout(() => setToast(""), 3000);
    }
  }, [from, to]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  const range = { from: from || undefined, to: to || undefined };

  return (
    <AdminLayout title="Analytics & Reports" toast={toast}>
      <div className="flex flex-wrap items-end gap-2 rounded-xl border border-stone-200 bg-white p-3 shadow-sm">
        <label className="text-sm text-stone-600">
          From{" "}
          <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className={dateInputClass} />
        </label>
        <label className="text-sm text-stone-600">
          To{" "}
          <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className={dateInputClass} />
        </label>
        <span className="flex-1" />
        <button type="button" onClick={() => downloadAnalyticsCSV(range)} className={btnPrimary}>
          ⬇ Export CSV
        </button>
        <button type="button" onClick={() => openAnalyticsPDF(range)} className={btnGhost}>
          🖨 Export PDF
        </button>
      </div>

      {!data ? (
        <p className="text-sm text-stone-500">Computing analytics from the database…</p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard icon="👥" label="Verified users" value={data.users.verified} />
            <StatCard icon="⏳" label="Pending users" value={data.users.pending} />
            <StatCard icon="📦" label="Active listings" value={data.resources.active} />
            <StatCard icon="🤝" label="Completed exchanges" value={data.exchanges.completed} />
          </div>
          <div className="grid gap-5 lg:grid-cols-2">
            <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
              <h2 className="mb-3 font-bold text-emerald-950">Verified residents by barangay</h2>
              {(data.users.verifiedByBarangay || []).length === 0 ? (
                <p className="py-4 text-center text-sm text-stone-500">No verified residents found.</p>
              ) : (
                <dl className="divide-y divide-stone-100 text-sm">
                  {data.users.verifiedByBarangay.map((b) => (
                    <div key={b.barangay} className="flex items-center justify-between py-2">
                      <dt className="text-stone-600">{b.barangay}</dt>
                      <dd className="font-bold tabular-nums text-emerald-950">{b.verified}</dd>
                    </div>
                  ))}
                </dl>
              )}
            </div>
            <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
              <h2 className="mb-3 font-bold text-emerald-950">Listings by category</h2>
              <dl className="divide-y divide-stone-100 text-sm">
                <div className="flex items-center justify-between py-2">
                  <dt className="text-stone-600">Offers</dt>
                  <dd className="font-bold tabular-nums text-emerald-950">{data.resources.offers}</dd>
                </div>
                <div className="flex items-center justify-between py-2">
                  <dt className="text-stone-600">Needs</dt>
                  <dd className="font-bold tabular-nums text-emerald-950">{data.resources.needs}</dd>
                </div>
                <div className="flex items-center justify-between py-2">
                  <dt className="text-stone-600">Removed</dt>
                  <dd className="font-bold tabular-nums text-emerald-950">{data.resources.removed}</dd>
                </div>
              </dl>
            </div>
          </div>
        </>
      )}
    </AdminLayout>
  );
}
