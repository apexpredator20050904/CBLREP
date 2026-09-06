import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";

const ReportsPage = ({ showToast, reloadDashboard }) => {
  const [reports, setReports] = useState([]);
  const [status, setStatus] = useState("all");
  const [reviewing, setReviewing] = useState(null);
  const [notes, setNotes] = useState("");

  const load = useCallback(async () => {
    try {
      const data = await apiFetch(`/api/admin/reports?status=${encodeURIComponent(status)}`);
      setReports(data.reports || []);
    } catch (e) {
      showToast(e.message);
    }
  }, [status, showToast]);

  useEffect(() => {
    load();
  }, [load]);

  const decide = async (decision) => {
    if (decision !== "UNDER REVIEW" && !notes.trim())
      return showToast("An explanation is required for this decision.");
    try {
      await apiFetch(`/api/admin/reports/${reviewing.id}/resolve`, {
        method: "POST",
        body: JSON.stringify({ decision, notes }),
      });
      showToast(`Report marked ${decision}`);
      setReviewing(null);
      setNotes("");
      load();
      if (reloadDashboard) reloadDashboard();
    } catch (e) {
      showToast(e.message);
    }
  };

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <select className="filter-select" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="all">All statuses</option>
          <option value="PENDING">Pending</option>
          <option value="UNDER REVIEW">Under review</option>
          <option value="RESOLVED">Resolved</option>
          <option value="DISMISSED">Dismissed</option>
        </select>
        <span className="filter-count">{reports.length} report(s)</span>
      </div>

      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr><th>Subject</th><th>Reporter</th><th>Reason</th><th>Status</th><th>Action</th></tr>
          </thead>
          <tbody>
            {reports.length === 0 ? (
              <tr><td colSpan="5" className="table-empty">No reports found.</td></tr>
            ) : (
              reports.map((r) => (
                <tr key={r.id}>
                  <td className="table-strong">{r.subject_label}</td>
                  <td>{r.reporter_name || r.reporter_email}</td>
                  <td>{r.reason}</td>
                  <td>
                    <span className={`type-badge ${r.status === "PENDING" ? "badge-warn" : r.status === "RESOLVED" ? "badge-success" : "badge-default"}`}>
                      {r.status}
                    </span>
                  </td>
                  <td className="table-actions">
                    <button type="button" onClick={() => { setReviewing(r); setNotes(""); }}>Review</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {reviewing ? (
        <div className="modal-backdrop" onClick={() => setReviewing(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3>Review report #{reviewing.id}</h3>
            <p>{reviewing.subject_label}</p>
            <p><strong>Filed by:</strong> {reviewing.reporter_name || reviewing.reporter_email}</p>
            <p><strong>Reason:</strong> {reviewing.reason}</p>
            <textarea
              rows={3}
              placeholder="Explanation / resolution notes (required for resolve or dismiss)"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
            <div className="table-actions" style={{ marginTop: 10 }}>
              <button type="button" onClick={() => decide("UNDER REVIEW")}>Mark under review</button>
              <button type="button" onClick={() => decide("RESOLVED")}>Resolve</button>
              <button type="button" className="warn" onClick={() => decide("DISMISSED")}>Dismiss</button>
              <button type="button" className="close-btn" onClick={() => setReviewing(null)}>Cancel</button>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
};

export default ReportsPage;
