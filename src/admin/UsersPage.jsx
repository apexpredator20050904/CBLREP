import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";

const statusBadge = (u) =>
  u.account_status === "Suspended" ? "badge-danger" : "badge-success";

const UsersPage = ({ mode = "all", showToast }) => {
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState("");
  const [role, setRole] = useState("all");
  const [error, setError] = useState("");
  const [activity, setActivity] = useState(null);

  const load = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (q) params.set("q", q);
      if (role !== "all") params.set("role", role);
      if (mode === "suspended") params.set("status", "suspended");
      const data = await apiFetch(`/api/admin/users?${params.toString()}`);
      setUsers(data.users || []);
      setError("");
    } catch (e) {
      setError(e.message);
    }
  }, [q, role, mode]);

  useEffect(() => {
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
  }, [load]);

  const act = async (id, action, body = {}) => {
    try {
      await apiFetch(`/api/admin/users/${id}/${action}`, {
        method: "POST",
        body: JSON.stringify(body),
      });
      showToast(`User ${action} successful`);
      load();
    } catch (e) {
      showToast(e.message);
    }
  };

  const suspend = (u) => {
    const reason = window.prompt(
      `Reason for suspending ${u.name}? (required for accountability)`,
    );
    if (!reason || !reason.trim()) return showToast("A reason is required.");
    act(u.id, "suspend", { reason });
  };
  const reject = (u) => {
    const reason = window.prompt(`Reason for rejecting ${u.name}'s verification?`);
    if (!reason || !reason.trim()) return showToast("A reason is required.");
    act(u.id, "reject", { reason });
  };

  const openActivity = async (u) => {
    try {
      setActivity(await apiFetch(`/api/admin/users/${u.id}/activity`));
    } catch (e) {
      showToast(e.message);
    }
  };

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <input
          className="filter-input"
          placeholder="Search name, email or phone…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <select className="filter-select" value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="all">All roles</option>
          <option value="member">General Member</option>
          <option value="community">Community Organization Manager</option>
          <option value="admin">System Administrator</option>
        </select>
      </div>

      {error ? <div className="table-card"><p className="table-empty">{error}</p></div> : null}

      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th><th>Email</th><th>Role</th>
              <th>Verification</th><th>Account</th><th>Registered</th><th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.length === 0 ? (
              <tr><td colSpan="7" className="table-empty">No users match the current filters.</td></tr>
            ) : (
              users.map((u) => (
                <tr key={u.id}>
                  <td className="table-strong">{u.name}</td>
                  <td>{u.email}</td>
                  <td><span className="type-badge badge-default">{u.role}</span></td>
                  <td>{u.verification_status}</td>
                  <td><span className={`type-badge ${statusBadge(u)}`}>{u.account_status}</span></td>
                  <td>{u.date_registered}</td>
                  <td className="table-actions">
                    <button type="button" onClick={() => openActivity(u)}>View</button>
                    {!u.verification_status.startsWith("Verified") && !u.verification_status.startsWith("Rejected") ? (
                      <button type="button" onClick={() => act(u.id, "verify")}>Verify</button>
                    ) : null}
                    {u.verification_status === "Pending Review" ? (
                      <button type="button" className="warn" onClick={() => reject(u)}>Reject</button>
                    ) : null}
                    {u.account_status === "Active" ? (
                      <button type="button" className="danger" onClick={() => suspend(u)}>Suspend</button>
                    ) : (
                      <button type="button" onClick={() => act(u.id, "reactivate")}>Reactivate</button>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {activity ? (
        <div className="modal-backdrop" onClick={() => setActivity(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3>User Activity — {activity.user.fullName}</h3>
            <p>{activity.user.email} · {activity.user.barangay} · {activity.user.role}</p>
            <ul>
              <li>Listings posted: {activity.listings.length}</li>
              <li>Time-Bank exchanges: {activity.tbTransactions.length}</li>
              <li>Reports filed: {activity.reportsFiledBy.length}</li>
              <li>Audit records: {activity.auditsMentioning.length}</li>
            </ul>
            {activity.auditsMentioning.length > 0 ? (
              <>
                <strong>Administrative history</strong>
                <ul>
                  {activity.auditsMentioning.slice(-5).map((a) => (
                    <li key={a.id}>{a.action} — {a.description}</li>
                  ))}
                </ul>
              </>
            ) : null}
            <button type="button" className="close-btn" onClick={() => setActivity(null)}>Close</button>
          </div>
        </div>
      ) : null}
    </section>
  );
};

export default UsersPage;
