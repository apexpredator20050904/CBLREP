// ─────────────────────────────────────────────────────────────
// CBLRE Admin · All users (/admin/users)
// Directory of residents + admins: search, suspend/reactivate,
// per-user activity drill-down. (Part 1: state + actions.)
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  FilterBar,
  StatusBadge,
  TableCard,
  selectClass,
  tableActionBtn,
  tableActionDanger,
  tableClass,
  tdClass,
  tdStrongClass,
  thClass,
  theadClass,
} from "../components/ui";
import { api, decideVerification } from "../services/adminApi";

export default function UsersPage() {
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState("");
  const [role, setRole] = useState("all");
  const [toast, setToast] = useState("");
  const [activity, setActivity] = useState(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      const params = {};
      if (q) params.q = q;
      if (role !== "all") params.role = role;
      const { data } = await api.get("/admin/users", { params });
      setUsers(data.users || []);
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load users.");
    }
  }, [q, role]);

  useEffect(() => {
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
  }, [load]);

  const suspend = async (u) => {
    const reason = window.prompt(`Reason for suspending ${u.name}? (required)`);
    if (!reason?.trim()) return flash("A reason is required.");
    try {
      await decideVerification(u.id, "suspend", { reason: reason.trim() });
      flash("User suspended.");
      load();
    } catch (e) {
      flash(e.message);
    }
  };

  const reactivate = async (u) => {
    try {
      await decideVerification(u.id, "reactivate");
      flash("User reactivated.");
      load();
    } catch (e) {
      flash(e.message);
    }
  };

  const openActivity = async (u) => {
    try {
      const { data } = await api.get(`/admin/users/${u.id}/activity`);
      setActivity(data);
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load activity.");
    }
  };

  return (
    <AdminLayout title="User Management" toast={toast}>
      <FilterBar count={`${users.length} user(s)`}>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search name, email or phone…"
          className="min-w-52 rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
        />
        <select value={role} onChange={(e) => setRole(e.target.value)} className={selectClass}>
          <option value="all">All roles</option>
          <option value="member">General Member</option>
          <option value="community">Community Organization Manager</option>
          <option value="admin">System Administrator</option>
        </select>
      </FilterBar>

      <TableCard>
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Name</th>
              <th className={thClass}>Email</th>
              <th className={thClass}>Role</th>
              <th className={thClass}>Verification</th>
              <th className={thClass}>Account</th>
              <th className={thClass}>Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {users.length === 0 ? (
              <EmptyRow colSpan={6}>No users match the current filters.</EmptyRow>
            ) : (
              users.map((u) => (
                <tr key={u.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{u.name}</td>
                  <td className={tdClass}>{u.email}</td>
                  <td className={tdClass}>{u.role}</td>
                  <td className={tdClass}>{u.verification_status}</td>
                  <td className={tdClass}>
                    <StatusBadge tone={u.account_status === "Suspended" ? "danger" : "success"}>
                      {u.account_status}
                    </StatusBadge>
                  </td>
                  <td className={tdClass}>
                    <div className="flex flex-wrap gap-1.5">
                      <button type="button" onClick={() => openActivity(u)} className={tableActionBtn}>View</button>
                      {u.account_status === "Active" ? (
                        <button type="button" onClick={() => suspend(u)} className={tableActionDanger}>Suspend</button>
                      ) : (
                        <button type="button" onClick={() => reactivate(u)} className={tableActionBtn}>Reactivate</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>

      {activity ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setActivity(null)}>
          <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="font-bold text-emerald-950">User Activity — {activity.user.fullName}</h3>
            <p className="mt-1 text-sm text-stone-500">{activity.user.email} · {activity.user.barangay}</p>
            <ul className="mt-4 space-y-1.5 text-sm text-stone-700">
              <li>Listings posted: <strong>{activity.listings.length}</strong></li>
              <li>Time-Bank exchanges: <strong>{activity.tbTransactions.length}</strong></li>
              <li>Reports filed: <strong>{activity.reportsFiledBy.length}</strong></li>
              <li>Audit records: <strong>{activity.auditsMentioning.length}</strong></li>
            </ul>
            <button type="button" onClick={() => setActivity(null)} className="mt-5 rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold hover:bg-stone-50">Close</button>
          </div>
        </div>
      ) : null}
    </AdminLayout>
  );
}
