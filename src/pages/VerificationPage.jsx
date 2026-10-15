// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Verification panel (/admin/verification)
// Trinidad resident queue from the Flutter app, filterable by barangay.
// Approve / request-info / reject via POST /admin/users/{id}/{action}.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  FilterBar,
  StatusBadge,
  TableCard,
  UserAvatar,
  selectClass,
  tableActionBtn,
  tableActionDanger,
  tableActionWarn,
  tableClass,
  tdClass,
  tdStrongClass,
  thClass,
  theadClass,
} from "../components/ui";
import { TRINIDAD_BARANGAYS } from "../config/community";
import { decideVerification, fetchPendingVerifications, openVerificationDocument } from "../services/adminApi";

export default function VerificationPage() {
  const [data, setData] = useState(null);
  const [barangay, setBarangay] = useState("");
  const [toast, setToast] = useState("");
  const [busyId, setBusyId] = useState(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      setData(await fetchPendingVerifications(barangay));
    } catch (e) {
      flash(e.message);
    }
  }, [barangay]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  // Open the member's submitted proof of residency in a new tab. The document
  // is fetched with the admin bearer token, so it is never a public URL.
  const viewDoc = async (id) => {
    try {
      await openVerificationDocument(id);
    } catch (e) {
      flash(e.message);
    }
  };

  // Collect the action payload (reason / student capture), then decide.
  const act = async (id, action) => {
    let body = {};
    if (action === "reject") {
      const reason = window.prompt("Reason for rejection (recorded for accountability):");
      if (!reason?.trim()) return flash("A reason is required.");
      body = { reason: reason.trim() };
    }
    if (action === "request-info") {
      const info = window.prompt("What additional information do you need?");
      if (!info?.trim()) return flash("Please describe the information needed.");
      body = { reason: info.trim() };
    }
    if (action === "verify") {
      const school = window.prompt(
        "Is this member a student? If yes, enter their school name. (Leave blank if not.)"
      );
      if (school === null) return; // dialog cancelled
      body = school.trim()
        ? { student_status: true, student_school: school.trim() }
        : { student_status: false, student_school: null };
    }
    setBusyId(id);
    try {
      await decideVerification(id, action, body);
      flash(`Verification ${action} recorded.`);
      load();
    } catch (e) {
      flash(e.message);
    } finally {
      setBusyId(null);
    }
  };

  return (
    <AdminLayout title="Verification Management" toast={toast}>
      <FilterBar count={data ? `${data.pending.length} pending` : ""}>
        <select value={barangay} onChange={(e) => setBarangay(e.target.value)} className={selectClass}>
          <option value="">All Trinidad barangays</option>
          {TRINIDAD_BARANGAYS.map((b) => (
            <option key={b} value={b}>{b}</option>
          ))}
        </select>
      </FilterBar>

      <TableCard title={`Pending requests (${data?.pending.length ?? 0})`}>
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Name</th>
              <th className={thClass}>Email</th>
              <th className={thClass}>Barangay</th>
              <th className={thClass}>Student</th>
              <th className={thClass}>Proof of residency</th>
              <th className={thClass}>Requested</th>
              <th className={thClass}>Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {!data ? (
              <EmptyRow colSpan={7}>Loading verification queue…</EmptyRow>
            ) : data.pending.length === 0 ? (
              <EmptyRow colSpan={7}>No pending verification requests.</EmptyRow>
            ) : (
              data.pending.map((u) => (
                <tr key={u.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>
                    <div className="flex items-center gap-3">
                      <UserAvatar name={u.fullName} url={u.avatar_url} />
                      <span>{u.fullName}</span>
                    </div>
                  </td>
                  <td className={tdClass}>{u.email}</td>
                  <td className={tdClass}>{u.barangay}</td>
                  <td className={tdClass}>
                    {u.is_student ? (
                      <StatusBadge tone="warn">{u.student_school || "Yes"}</StatusBadge>
                    ) : (
                      <span className="text-stone-400">—</span>
                    )}
                  </td>
                  <td className={tdClass}>
                    {u.has_document ? (
                      <button
                        type="button"
                        onClick={() => viewDoc(u.id)}
                        className={tableActionBtn}
                        title="Open the submitted proof of residency"
                      >
                        View {u.document_type ? `· ${u.document_type}` : "document"}
                      </button>
                    ) : (
                      <span className="text-stone-400">No document</span>
                    )}
                  </td>
                  <td className={tdClass}>{u.requested_at}</td>
                  <td className={tdClass}>
                    <div className="flex flex-wrap gap-1.5">
                      <button type="button" disabled={busyId === u.id} onClick={() => act(u.id, "verify")} className={tableActionBtn}>Approve</button>
                      <button type="button" disabled={busyId === u.id} onClick={() => act(u.id, "reject")} className={tableActionDanger}>Reject</button>
                      <button type="button" disabled={busyId === u.id} onClick={() => act(u.id, "request-info")} className={tableActionWarn}>Request info</button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>

      <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <h2 className="mb-2 font-bold text-emerald-950">Decision history (audit trail)</h2>
        {(data?.decided || []).length === 0 ? (
          <p className="py-4 text-center text-sm text-stone-500">No decisions recorded yet.</p>
        ) : (
          <ul className="divide-y divide-stone-100">
            {data.decided.map((d) => (
              <li key={d.id} className="flex items-start justify-between gap-4 py-3">
                <div>
                  <p className="font-semibold text-emerald-950">{d.action}</p>
                  <p className="text-sm text-stone-500">{d.description}</p>
                </div>
                <span className="whitespace-nowrap text-xs text-stone-400">{d.date} {d.time}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </AdminLayout>
  );
}
