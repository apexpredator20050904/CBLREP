// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Reports & moderation (/admin/reports)
// ─────────────────────────────────────────────────────────────
// User-filed reports queue: GET /admin/reports, resolve via
// POST /admin/reports/{id}/resolve (VerificationReportsController).
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  StatusBadge,
  TableCard,
  tableActionBtn,
  tableClass,
  tdClass,
  tdStrongClass,
  thClass,
  theadClass,
} from "../components/ui";
import { api, errMsg } from "../services/adminApi";

const toneFor = (s) => {
  const v = String(s || "").toLowerCase();
  if (v.includes("resolv") || v.includes("dismiss")) return "success";
  if (v.includes("pend") || v.includes("open")) return "warn";
  return "default";
};

export default function ReportsPage() {
  const [reports, setReports] = useState([]);
  const [toast, setToast] = useState("");
  const [busyId, setBusyId] = useState(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/admin/reports");
      setReports(data.reports || data || []);
    } catch (e) {
      flash(errMsg(e, "Failed to load reports."));
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const resolve = async (r, action = "resolve") => {
    setBusyId(r.id);
    try {
      await api.post(`/admin/reports/${r.id}/resolve`, { action });
      flash("Report resolved.");
      load();
    } catch (e) {
      flash(errMsg(e, "Failed to resolve report."));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <AdminLayout title="Reports & Moderation" toast={toast}>
      <TableCard title={`Member reports (${reports.length})`}>
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Report</th>
              <th className={thClass}>Reporter</th>
              <th className={thClass}>Status</th>
              <th className={thClass}>Filed</th>
              <th className={thClass}>Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {reports.length === 0 ? (
              <EmptyRow colSpan={5}>No reports filed. The queue is clear. ✅</EmptyRow>
            ) : (
              reports.map((r) => (
                <tr key={r.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{r.title || r.reason || `Report #${r.id}`}</td>
                  <td className={tdClass}>{r.reporter_name || r.user?.name || "—"}</td>
                  <td className={tdClass}>
                    <StatusBadge tone={toneFor(r.status)}>{r.status || "pending"}</StatusBadge>
                  </td>
                  <td className={tdClass}>{r.created_at || "—"}</td>
                  <td className={tdClass}>
                    <button
                      type="button"
                      disabled={busyId === r.id}
                      onClick={() => resolve(r)}
                      className={tableActionBtn}
                    >
                      Resolve
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>
    </AdminLayout>
  );
}
