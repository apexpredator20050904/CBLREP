// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Time Bank console (/admin/timebank)
// ─────────────────────────────────────────────────────────────
// Read model for time-credit activity: GET /admin/timebank returns the
// summary + transaction ledger (AdminPortalController::adminTimebank).
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  StatCard,
  TableCard,
  tableClass,
  tdClass,
  tdStrongClass,
  thClass,
  theadClass,
} from "../components/ui";
import { api, errMsg } from "../services/adminApi";

export default function TimeBankPage() {
  const [data, setData] = useState(null);
  const [toast, setToast] = useState("");

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      const res = await api.get("/admin/timebank");
      setData(res.data);
    } catch (e) {
      flash(errMsg(e, "Failed to load Time Bank ledger."));
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const summary = data?.summary || {};
  const ledger = data?.transactions || data?.ledger || [];

  return (
    <AdminLayout title="Time Bank" toast={toast}>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon="⏱️" label="Total transactions" value={summary.total ?? ledger.length} />
        <StatCard icon="🤝" label="Completed" value={summary.completed ?? 0} />
        <StatCard icon="⏳" label="Pending confirmation" value={summary.pending ?? 0} />
        <StatCard icon="🕒" label="Hours delivered" value={summary.hoursTotal ?? 0} accent />
      </div>

      <TableCard title="Time-credit ledger">
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Service</th>
              <th className={thClass}>Provider → Requester</th>
              <th className={thClass}>Hours</th>
              <th className={thClass}>Status</th>
              <th className={thClass}>Updated</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {ledger.length === 0 ? (
              <EmptyRow colSpan={5}>No Time Bank transactions recorded yet.</EmptyRow>
            ) : (
              ledger.map((t) => (
                <tr key={t.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{t.service_title || t.title || `#${t.id}`}</td>
                  <td className={tdClass}>
                    {[t.provider_name, t.requester_name].filter(Boolean).join(" → ") || "—"}
                  </td>
                  <td className={tdClass}>{t.hours ?? t.credits ?? "—"}</td>
                  <td className={tdClass}>{t.status || "—"}</td>
                  <td className={tdClass}>{t.updated_at || t.created_at || "—"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>
    </AdminLayout>
  );
}
