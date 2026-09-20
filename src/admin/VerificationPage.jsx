import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";
import { TRINIDAD_BARANGAYS } from "../config/community";

const VerificationPage = ({ showToast }) => {
  const [data, setData] = useState(null);
  const [barangayFilter, setBarangayFilter] = useState("");

  const load = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (barangayFilter) params.set("barangay", barangayFilter);
      setData(await apiFetch(`/api/admin/verification?${params.toString()}`));
    } catch (e) {
      showToast(e.message);
    }
  }, [showToast, barangayFilter]);

  useEffect(() => {
    load();
  }, [load]);

  const act = async (id, action) => {
    let body = {};
    if (action === "reject") {
      const reason = window.prompt("Reason for rejection (recorded for accountability):");
      if (!reason || !reason.trim()) return showToast("A reason is required.");
      body = { reason };
    }
    if (action === "request-info") {
      const info = window.prompt("What additional information do you need?");
      if (!info || !info.trim()) return showToast("Please describe the information needed.");
      body = { reason: info };
    }
    if (action === "verify") {
      // Check if the member is a student.
      const studentSchool = window.prompt(
        "Is this member a student? If yes, enter their school/university name. (Leave blank if not a student.)"
      );
      if (studentSchool !== null) {
        if (studentSchool.trim()) {
          body = { student_status: true, student_school: studentSchool.trim() };
        } else {
          body = { student_status: false, student_school: null };
        }
      }
    }
    try {
      await apiFetch(`/api/admin/users/${id}/${action}`, {
        method: "POST",
        body: JSON.stringify(body),
      });
      showToast(`Verification ${action} recorded`);
      load();
    } catch (e) {
      showToast(e.message);
    }
  };

  if (!data) return <section className="page-stack"><p>Loading verification queue…</p></section>;

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <select
          className="filter-select"
          value={barangayFilter}
          onChange={(e) => setBarangayFilter(e.target.value)}
        >
          <option value="">All Trinidad barangays</option>
          {TRINIDAD_BARANGAYS.map((b) => (
            <option key={b} value={b}>{b}</option>
          ))}
        </select>
        <span className="filter-count">{data.pending.length} pending • {data.decided.length} decided</span>
      </div>

      <div className="table-card">
        <h3 className="table-card-title">Pending verification requests ({data.pending.length})</h3>
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th><th>Email</th><th>Barangay</th>
              <th>Student</th><th>Role</th><th>Requested</th><th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {data.pending.length === 0 ? (
              <tr><td colSpan="7" className="table-empty">No pending verification requests.</td></tr>
            ) : (
              data.pending.map((u) => (
                <tr key={u.id}>
                  <td className="table-strong">{u.fullName}</td>
                  <td>{u.email}</td>
                  <td>{u.barangay}</td>
                  <td>
                    {u.is_student ? (
                      <span className="type-badge badge-warn">
                        {u.student_school || "Yes"}
                      </span>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{u.role}</td>
                  <td>{u.requested_at}</td>
                  <td className="table-actions">
                    <button type="button" onClick={() => act(u.id, "verify")}>Approve</button>
                    <button type="button" className="warn" onClick={() => act(u.id, "request-info")}>Request info</button>
                    <button type="button" className="danger" onClick={() => act(u.id, "reject")}>Reject</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="dashboard-activity-card">
        <div className="dashboard-section-header">
          <h3 className="dashboard-section-title">Decision history (audit trail)</h3>
        </div>
        {(data.decided || []).length === 0 ? (
          <p className="table-empty">No verification decisions recorded yet.</p>
        ) : (
          data.decided.map((d) => (
            <div className="activity-row" key={d.id}>
              <div>
                <strong>{d.action}</strong>
                <p>{d.description}</p>
              </div>
              <small>{d.date} {d.time}</small>
            </div>
          ))
        )}
      </div>
    </section>
  );
};

export default VerificationPage;
