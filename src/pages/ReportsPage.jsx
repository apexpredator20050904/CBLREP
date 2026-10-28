// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Reports & moderation (/admin/reports)
// ─────────────────────────────────────────────────────────────
// User-filed reports queue: GET /admin/safety-reports, resolve via
// PATCH /admin/safety-reports/{id} (ReportController).
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
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
  if (v.includes("action")) return "success";
  if (v.includes("review")) return "info";
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
      const { data } = await api.get("/admin/safety-reports");
      setReports(data.reports || data || []);
    } catch (e) {
      flash(errMsg(e, "Failed to load reports."));
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  const resolve = async (r) => {
    setBusyId(r.id);
    try {
      await api.patch(`/admin/safety-reports/${r.id}`, {
        status: "action_taken",
      });
      flash("Report marked as action taken.");
      load();
    } catch (e) {
      flash(errMsg(e, "Failed to resolve report."));
    } finally {
      setBusyId(null);
    }
  };

  const markReviewed = async (r) => {
    setBusyId(r.id);
    try {
      await api.patch(`/admin/safety-reports/${r.id}`, {
        status: "reviewed",
      });
      flash("Report marked as reviewed.");
      load();
    } catch (e) {
      flash(errMsg(e, "Failed to update report."));
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
              <th className={thClass}>Reason</th>
              <th className={thClass}>Status</th>
              <th className={thClass}>Filed</th>
              <th className={thClass}>Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {reports.length === 0 ? (
              <EmptyRow colSpan={6}>No reports filed. The queue is clear. ✅</EmptyRow>
            ) : (
              reports.map((r) => (
                <tr key={r.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{r.subject_label || r.title || `Report #${r.id}`}</td>
                  <td className={tdClass}>{r.reporter_name || r.reporter?.name || "—"}</td>
                  <td className={tdClass}>{r.reason_label || r.reason || "—"}</td>
                  <td className={tdClass}>
                    <StatusBadge tone={toneFor(r.status)}>{r.status_label || r.status || "pending"}</StatusBadge>
                  </td>
                  <td className={tdClass}>{r.created_at ? new Date(r.created_at).toLocaleString() : "—"}</td>
                  <td className={tdClass}>
                    {r.status === "pending" ? (
                      <div className="flex gap-2">
                        <button
                          type="button"
                          disabled={busyId === r.id}
                          onClick={() => markReviewed(r)}
                          className={tableActionBtn}
                        >
                          Mark Reviewed
                        </button>
                        <button
                          type="button"
                          disabled={busyId === r.id}
                          onClick={() => resolve(r)}
                          className={tableActionBtn}
                        >
                          Action Taken
                        </button>
                      </div>
                    ) : (
                      <span className="text-xs text-stone-500">—</span>
                    )}
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
