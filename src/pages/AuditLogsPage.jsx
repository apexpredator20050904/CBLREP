// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Audit logs (/admin/audit-logs)
// READ-ONLY immutable trail of admin decisions. Search filters locally.
// ─────────────────────────────────────────────────────────────
import { useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { EmptyRow, TableCard, tdClass, tdStrongClass, thClass, theadClass, tableClass } from "../components/ui";
import { api } from "../services/adminApi";

export default function AuditLogsPage() {
  const [logs, setLogs] = useState([]);
  const [q, setQ] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .get("/admin/audit-logs")
      .then(({ data }) => setLogs(data.logs || []))
      .catch((e) => setError(e?.response?.data?.message || "Failed to load audit logs."));
  }, []);

  const filtered = logs.filter(
    (l) =>
      !q ||
      [l.admin, l.action, l.description].some((f) =>
        String(f || "").toLowerCase().includes(q.toLowerCase())
      )
  );

  return (
    <AdminLayout title="Audit Logs">
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search admin, action or description…"
        className="w-full rounded-xl border border-stone-200 bg-white px-4 py-2.5 text-sm shadow-sm focus:border-emerald-500 focus:outline-none"
      />
      {error ? <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p> : null}
      <TableCard>
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Admin</th>
              <th className={thClass}>Action</th>
              <th className={thClass}>Target</th>
              <th className={thClass}>Description</th>
              <th className={thClass}>Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {filtered.length === 0 ? (
              <EmptyRow colSpan={5}>No audit entries recorded yet.</EmptyRow>
            ) : (
              filtered.map((l) => (
                <tr key={`${l.id}-${l.stamp}`} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{l.admin}</td>
                  <td className={tdClass}>{l.action}</td>
                  <td className={tdClass}>{l.target_type ? `${l.target_type} #${l.target_id ?? "—"}` : "—"}</td>
                  <td className={tdClass}>{l.description}</td>
                  <td className={tdClass}>{l.date} {l.time}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>
      <p className="text-center text-xs text-stone-400">
        Audit logs are immutable and cannot be edited or deleted from the portal.
      </p>
    </AdminLayout>
  );
}
