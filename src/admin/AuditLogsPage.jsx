import { useEffect, useState } from "react";
import { apiFetch } from "./api";

// Audit logs are READ-ONLY by design — there is no write action on this page.
const AuditLogsPage = () => {
  const [logs, setLogs] = useState([]);
  const [q, setQ] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    apiFetch("/api/admin/audit-logs")
      .then((d) => setLogs(d.logs || []))
      .catch((e) => setError(e.message));
  }, []);

  const filtered = logs.filter(
    (l) =>
      !q ||
      [l.admin, l.action, l.description].some((f) =>
        String(f || "").toLowerCase().includes(q.toLowerCase()),
      ),
  );

  return (
    <section className="page-stack">
      <input
        className="filter-input"
        placeholder="Search admin, action or description…"
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      {error ? <div className="table-card"><p className="table-empty">{error}</p></div> : null}
      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr>
              <th>Admin</th><th>Action</th><th>Target</th>
              <th>Description</th><th>Date</th><th>Time</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan="6" className="table-empty">
                  {error ? "" : "No audit entries recorded yet. Administrative actions will appear here."}
                </td>
              </tr>
            ) : (
              filtered.map((l) => (
                <tr key={`${l.id}-${l.stamp}`}>
                  <td className="table-strong">{l.admin}</td>
                  <td><span className="type-badge badge-default">{l.action}</span></td>
                  <td>{l.target_type ? `${l.target_type} #${l.target_id ?? "—"}` : "—"}</td>
                  <td>{l.description}</td>
                  <td>{l.date}</td>
                  <td>{l.time}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      <p className="table-empty">
        Audit logs are immutable and cannot be edited or deleted from the portal.
      </p>
    </section>
  );
};

export default AuditLogsPage;
