// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Analytics & reporting (/admin/analytics)
// Summary cards + per-barangay breakdowns (GET /admin/analytics),
// with CSV and PDF downloads of the same figures over the selected range.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import { StatCard, btnGhost, btnPrimary, dateInputClass } from "../components/ui";
import {
  exportAnalyticsCSV,
  exportAnalyticsPDF,
  fetchAnalytics,
} from "../services/adminApi";

export default function AnalyticsPage() {
  const [data, setData] = useState(null);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [toast, setToast] = useState("");
  // Which export is in flight, so each button can disable itself without
  // blocking the other or the date inputs.
  const [exporting, setExporting] = useState(null);

  const flash = useCallback((message) => {
    setToast(message);
    setTimeout(() => setToast(""), 3000);
  }, []);

  const load = useCallback(async () => {
    try {
      setData(await fetchAnalytics({ from: from || undefined, to: to || undefined }));
    } catch (e) {
      flash(e.message);
    }
  }, [from, to, flash]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  const range = { from: from || undefined, to: to || undefined };

  /**
   * Shared body for both export buttons. `kind` selects the service call and
   * the noun used in the success toast, keeping the two handlers free of
   * duplicated try/catch/finally bookkeeping.
   */
  const runExport = useCallback(
    async (kind) => {
      setExporting(kind);
      try {
        const filename =
          kind === "csv"
            ? await exportAnalyticsCSV(range)
            : await exportAnalyticsPDF(range);
        flash(`Downloaded ${filename}`);
      } catch (e) {
        // The service unwraps the blob-wrapped JSON body, so e.message is the
        // server's real reason (e.g. rate limited) rather than a network error.
        flash(e.message);
      } finally {
        setExporting(null);
      }
    },
    [range.from, range.to, flash] // eslint-disable-line react-hooks/exhaustive-deps
  );

  const handleExportCSV = useCallback(() => runExport("csv"), [runExport]);
  const handleExportPDF = useCallback(() => runExport("pdf"), [runExport]);

  const exportingAny = exporting !== null;

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
        <button
          type="button"
          onClick={handleExportCSV}
          disabled={exportingAny}
          className={`${btnPrimary} disabled:cursor-not-allowed disabled:opacity-60`}
        >
          {exporting === "csv" ? "⏳ Preparing CSV…" : "⬇ Export CSV"}
        </button>
        <button
          type="button"
          onClick={handleExportPDF}
          disabled={exportingAny}
          className={`${btnGhost} disabled:cursor-not-allowed disabled:opacity-60`}
        >
          {exporting === "pdf" ? "⏳ Building PDF…" : "📄 Export PDF"}
        </button>
      </div>

      {!data ? (
        <p className="text-sm text-stone-500">Computing analytics from the database…</p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard icon="👥" label="Verified users" value={data?.users?.verified ?? 0} />
            <StatCard icon="⏳" label="Pending users" value={data?.users?.pending ?? 0} />
            <StatCard icon="📦" label="Active listings" value={data?.resources?.active ?? 0} />
            <StatCard icon="🤝" label="Completed exchanges" value={data?.exchanges?.completed ?? 0} />
          </div>
          <div className="grid gap-5 lg:grid-cols-2">
            <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
              <h2 className="mb-3 font-bold text-emerald-950">Verified residents by barangay</h2>
              {(!data || !data.users || !Array.isArray(data.users.verifiedByBarangay) || data.users.verifiedByBarangay.length === 0) ? (
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
                  <dd className="font-bold tabular-nums text-emerald-950">{data?.resources?.offers ?? 0}</dd>
                </div>
                <div className="flex items-center justify-between py-2">
                  <dt className="text-stone-600">Needs</dt>
                  <dd className="font-bold tabular-nums text-emerald-950">{data?.resources?.needs ?? 0}</dd>
                </div>
                <div className="flex items-center justify-between py-2">
                  <dt className="text-stone-600">Removed</dt>
                  <dd className="font-bold tabular-nums text-emerald-950">{data?.resources?.removed ?? 0}</dd>
                </div>
              </dl>
            </div>
          </div>
        </>
      )}
    </AdminLayout>
  );
}
