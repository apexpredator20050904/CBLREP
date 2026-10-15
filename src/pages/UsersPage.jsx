// ─────────────────────────────────────────────────────────────
// CBLRE Admin · All users (/admin/users)
// Directory of residents + admins: search, suspend/reactivate,
// per-user activity drill-down, and account creation/editing.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import ConfirmModal from "../components/ConfirmModal";
import { useConfirm } from "../components/useConfirm";
import DataTable from "../components/DataTable";
import { StatusBadge, UserAvatar, btnPrimary, tableActionBtn, tableActionDanger } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { TRINIDAD_BARANGAYS } from "../config/community";
import { api, decideVerification, createAccount, updateAccount, updateAccountRole, deleteAccount } from "../services/adminApi";

const ROLE_OPTIONS = [
  { value: "user", label: "General Member" },
  { value: "admin", label: "System Administrator" },
  { value: "super_admin", label: "Super Administrator" },
];

const EMPTY_FORM = {
  name: "",
  email: "",
  password: "",
  password_confirmation: "",
  role: "user",
  account_status: "active",
  barangay_or_location: "",
  purok_sitio: "",
  student_status: false,
  student_school: "",
};

export default function UsersPage() {
  const { user: me } = useAuth();
  const isSuper = String(me?.raw_role || "") === "super_admin";

  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState("");
  const [activity, setActivity] = useState(null);
  const [modal, setModal] = useState(null); // { mode: "create"|"edit", user }
  const [form, setForm] = useState(EMPTY_FORM);
  const [fieldErrors, setFieldErrors] = useState({});
  const [busy, setBusy] = useState(false);
  const { close, setConfirm, state } = useConfirm();

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await api.get("/admin/users");
      setUsers(data.users || []);
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load users.");
      setUsers([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  const suspend = (u) => {
    const reason = window.prompt(`Reason for suspending ${u.name}? (required)`);
    if (!reason?.trim()) return flash("A reason is required.");
    setConfirm({
      title: `Suspend ${u.name}?`,
      message: `Suspend ${u.name} (${u.email})? They will not be able to log in. Reason: "${reason.trim()}".`,
      confirmLabel: "Suspend",
      destructive: true,
      onConfirm: async () => {
        try {
          await decideVerification(u.id, "suspend", { reason: reason.trim() });
          flash("User suspended.");
          load();
        } catch (e) {
          flash(e.message);
        }
      },
    });
  };

  const reactivate = (u) => {
    setConfirm({
      title: `Reactivate ${u.name}?`,
      message: `Reactivate ${u.name} (${u.email})? They will regain full access.`,
      confirmLabel: "Reactivate",
      destructive: false,
      onConfirm: async () => {
        try {
          await decideVerification(u.id, "reactivate");
          flash("User reactivated.");
          load();
        } catch (e) {
          flash(e.message);
        }
      },
    });
  };

  // ── Account CRUD handlers ──────────────────────────────────────────

  const openCreate = () => {
    setForm({ ...EMPTY_FORM, role: isSuper ? "user" : "user" });
    setFieldErrors({});
    setModal({ mode: "create" });
  };

  const openEdit = (u) => {
    setForm({
      name: u.name,
      email: u.email,
      password: "",
      password_confirmation: "",
      role: u.raw_role,
      account_status: u.account_status,
      barangay_or_location: u.barangay_or_location || "",
      purok_sitio: u.purok_sitio || "",
      student_status: !!u.student_status,
      student_school: u.student_school || "",
    });
    setFieldErrors({});
    setModal({ mode: "edit", user: u });
  };

  const setField = (key, value) => setForm((f) => ({ ...f, [key]: value }));

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setFieldErrors({});
    try {
      if (modal.mode === "create") {
        await createAccount({
          name: form.name,
          email: form.email,
          password: form.password,
          password_confirmation: form.password_confirmation,
          role: form.role,
          barangay_or_location: form.barangay_or_location || undefined,
          purok_sitio: form.purok_sitio || undefined,
          student_status: form.student_status,
          student_school: form.student_school || undefined,
        });
        flash("Account created successfully.");
      } else {
        const payload = {
          name: form.name,
          email: form.email,
          barangay_or_location: form.barangay_or_location || undefined,
          purok_sitio: form.purok_sitio || undefined,
          student_status: form.student_status,
          student_school: form.student_school || undefined,
          account_status: form.account_status,
        };
        if (form.password) {
          payload.password = form.password;
          payload.password_confirmation = form.password_confirmation;
        }
        await updateAccount(modal.user.id, payload);
        flash("Account updated successfully.");
      }
      setModal(null);
      load();
    } catch (err) {
      // Map Laravel 422 validation errors onto the form fields.
      const errors = err.cause?.response?.data?.errors;
      if (errors) setFieldErrors(errors);
      flash(err.message);
    } finally {
      setBusy(false);
    }
  };

  const changeRole = (u) => {
    const next = window.prompt(
      `New role for ${u.name}? Options: user, admin, super_admin`,
      u.raw_role,
    );
    if (!next || next === u.raw_role) return;
    if (!ROLE_OPTIONS.some((r) => r.value === next)) return flash("Unknown role.");
    setConfirm({
      title: `Change role of ${u.name}?`,
      message: `${u.name} is currently a ${u.role}. Change to "${next}"?`,
      confirmLabel: "Change role",
      destructive: false,
      onConfirm: async () => {
        try {
          await updateAccountRole(u.id, next);
          flash("Role updated.");
          load();
        } catch (err) {
          flash(err.message);
        }
      },
    });
  };

  const remove = (u) => {
    setConfirm({
      title: "Delete account?",
      message: `Permanently delete ${u.name} (${u.email})? This cannot be undone.`,
      confirmLabel: "Delete",
      destructive: true,
      onConfirm: async () => {
        await deleteAccount(u.id);
        flash("Account deleted.");
        load();
      },
    });
  };

  const openActivity = async (u) => {
    try {
      const { data } = await api.get(`/admin/users/${u.id}/activity`);
      setActivity(data);
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load activity.");
    }
  };

  const columns = [
    {
      key: "name",
      label: "Name",
      sortable: true,
      filter: { type: "text" },
      strong: true,
      render: (u) => (
        <div className="flex items-center gap-2">
          <UserAvatar name={u.name || u.fullName} url={u.avatar_url} size={32} />
          <div>
            <p>{u.name || u.fullName}</p>
            {u.is_student ? <p className="text-xs text-sky-700">🎓 {u.student_school || "Student"}</p> : null}
          </div>
        </div>
      ),
    },
    { key: "email", label: "Email", sortable: true, filter: { type: "text" } },
    {
      key: "role",
      label: "Role",
      sortable: true,
      filter: {
        type: "select",
        options: [
          { value: "General Member", label: "General Member" },
          { value: "System Administrator", label: "System Administrator" },
          { value: "Super Administrator", label: "Super Administrator" },
        ],
      },
    },
    {
      key: "verification_status",
      label: "Verification",
      render: (u) => (
        <StatusBadge tone={u.verification_status === "Verified" ? "success" : "warn"}>
          {u.verification_status}
        </StatusBadge>
      ),
      filter: {
        type: "select",
        options: [
          { value: "Verified", label: "Verified" },
          { value: "Pending", label: "Pending" },
          { value: "Rejected", label: "Rejected" },
          { value: "Unverified", label: "Unverified" },
        ],
      },
    },
    {
      key: "account_status",
      label: "Account",
      render: (u) => (
        <StatusBadge tone={u.account_status === "Suspended" ? "danger" : "success"}>
          {u.account_status}
        </StatusBadge>
      ),
      filter: {
        type: "select",
        options: [
          { value: "Active", label: "Active" },
          { value: "Suspended", label: "Suspended" },
        ],
      },
    },
    { key: "barangay_or_location", label: "Barangay", filter: { type: "text" } },
    { key: "resources_count", label: "Listings", sortable: true },
    { key: "date_registered", label: "Registered" },
    {
      key: "actions",
      label: "Actions",
      render: (u) => (
        <div className="flex flex-wrap gap-1.5">
          <button type="button" onClick={() => openActivity(u)} className={tableActionBtn}>View</button>
          <button type="button" onClick={() => openEdit(u)} className={tableActionBtn}>Edit</button>
          {u.account_status === "Active" ? (
            <button type="button" onClick={() => suspend(u)} className={tableActionDanger}>Suspend</button>
          ) : (
            <button type="button" onClick={() => reactivate(u)} className={tableActionBtn}>Reactivate</button>
          )}
          <button type="button" onClick={() => changeRole(u)} className={tableActionBtn}>Change role</button>
          {isSuper && u.id !== me?.id && (
            <button type="button" onClick={() => remove(u)} className={tableActionDanger}>Delete</button>
          )}
        </div>
      ),
    },
  ];

  // ── Create / Edit Modal ─────────────────────────────────────────────

  const modalContent = modal ? (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setModal(null)}>
      <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <h3 className="font-bold text-emerald-950">
          {modal.mode === "create" ? "Create new account" : `Edit ${modal.user.name}`}
        </h3>
        <p className="mt-1 text-sm text-stone-500">
          {modal.mode === "create" ? "Add a new user or administrator to the system." : "Update the account details below."}
        </p>

        <form onSubmit={submit} className="mt-5 space-y-4">
          {Object.entries(fieldErrors).length > 0 ? (
            <div className="rounded-lg border border-red-300 bg-red-50 p-3 text-sm text-red-700">
              <p className="font-semibold mb-1">Please fix the following errors:</p>
              <ul className="list-disc list-inside space-y-0.5">
                {Object.entries(fieldErrors).map(([key, vals]) => (
                  <li key={key}>{key === "password" ? "Password" : key}: {Array.isArray(vals) ? vals.join(", ") : vals}</li>
                ))}
              </ul>
            </div>
          ) : null}

          <label className="block text-sm">
            <span className="font-semibold text-stone-700">Full name</span>
            <input
              value={form.name}
              onChange={(e) => setField("name", e.target.value)}
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              placeholder="e.g. Maria Santos"
            />
          </label>

          <label className="block text-sm">
            <span className="font-semibold text-stone-700">Email</span>
            <input
              type="email"
              value={form.email}
              onChange={(e) => setField("email", e.target.value)}
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              placeholder="user@example.com"
            />
          </label>

          {modal.mode === "create" ? (
            <>
              <label className="block text-sm">
                <span className="font-semibold text-stone-700">Password</span>
                <input
                  type="password"
                  value={form.password}
                  onChange={(e) => setField("password", e.target.value)}
                  className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                  placeholder="Min. 8 characters"
                />
              </label>

              <label className="block text-sm">
                <span className="font-semibold text-stone-700">Confirm password</span>
                <input
                  type="password"
                  value={form.password_confirmation}
                  onChange={(e) => setField("password_confirmation", e.target.value)}
                  className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                  placeholder="Repeat password"
                />
              </label>
            </>
          ) : (
            <label className="block text-sm">
              <span className="font-semibold text-stone-700">New password <span className="text-stone-400">(leave blank to keep current)</span></span>
              <input
                type="password"
                value={form.password}
                onChange={(e) => setField("password", e.target.value)}
                className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                placeholder="Optional: set a new password"
              />
            </label>
          )}

          <label className="block text-sm">
            <span className="font-semibold text-stone-700">Role</span>
            <select
              value={form.role}
              onChange={(e) => setField("role", e.target.value)}
              disabled={!isSuper && modal.mode === "create"}
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
            >
              {ROLE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </label>

          <label className="block text-sm">
            <span className="font-semibold text-stone-700">Barangay</span>
            <select
              value={form.barangay_or_location}
              onChange={(e) => setField("barangay_or_location", e.target.value)}
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
            >
              <option value="">Select a barangay</option>
              {TRINIDAD_BARANGAYS.map((b) => (
                <option key={b} value={b}>{b}</option>
              ))}
            </select>
          </label>

          <label className="block text-sm">
            <span className="font-semibold text-stone-700">Purok / Sitio</span>
            <input
              value={form.purok_sitio}
              onChange={(e) => setField("purok_sitio", e.target.value)}
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              placeholder="e.g. Purok 4 / Sitio Tinubran"
            />
          </label>

          <div className="flex flex-wrap items-center gap-4 pt-1 text-sm">
            {modal.mode === "create" ? (
              <p className="text-xs text-stone-500">
                New members start <strong>Unverified</strong>. Residency is approved only
                through the <strong>Verification</strong> queue after the member submits proof.
              </p>
            ) : (
              <label className="flex items-center gap-2">
                <span className="font-semibold text-stone-700">Status</span>
                <select
                  value={form.account_status}
                  onChange={(e) => setField("account_status", e.target.value)}
                  className="rounded-lg border border-stone-300 px-2 py-1.5"
                >
                  <option value="active">Active</option>
                  <option value="suspended">Suspended</option>
                </select>
              </label>
            )}
            <label className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={form.student_status}
                onChange={(e) => setField("student_status", e.target.checked)}
              />
              <span className="font-semibold text-stone-700">Student</span>
            </label>
          </div>

          {form.student_status ? (
            <label className="block text-sm">
              <span className="font-semibold text-stone-700">School</span>
              <input
                value={form.student_school}
                onChange={(e) => setField("student_school", e.target.value)}
                className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                placeholder="e.g. Trinity College"
              />
            </label>
          ) : null}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={() => setModal(null)}
              disabled={busy}
              className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold hover:bg-stone-50"
            >
              Cancel
            </button>
            <button type="submit" disabled={busy} className={btnPrimary}>
              {busy ? "Saving…" : modal.mode === "create" ? "Create account" : "Save changes"}
            </button>
          </div>
        </form>
      </div>
    </div>
  ) : null;
  return (
    <AdminLayout title="User Management" toast={toast}>
      <div className="flex flex-wrap items-center justify-between gap-3 mb-5">
        <p className="text-sm text-stone-500">
          Manage all user accounts, roles, and permissions.
        </p>
        {isSuper && (
          <button type="button" onClick={openCreate} className={btnPrimary}>
            + Add account
          </button>
        )}
      </div>

      <DataTable
        columns={columns}
        rows={users}
        loading={loading}
        emptyMessage="No users match the current filters."
        initialSort={{ key: "name", dir: "asc" }}
      />

      {modalContent}

      {activity ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setActivity(null)}>
          <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="font-bold text-emerald-950">User Activity — {activity.user.fullName}</h3>
            <p className="mt-1 text-sm text-stone-500">{activity.user.email} · {activity.user.barangay}</p>
            <ul className="mt-4 space-y-1.5 text-sm text-stone-700">
              <li>Listings posted: <strong>{activity.listings.length}</strong></li>
              <li>Reports filed: <strong>{activity.reportsFiledBy.length}</strong></li>
              <li>Audit records: <strong>{activity.auditsMentioning.length}</strong></li>
            </ul>
            <button type="button" onClick={() => setActivity(null)} className="mt-5 rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold hover:bg-stone-50">Close</button>
          </div>
        </div>
      ) : null}
      <ConfirmModal
        open={state.open}
        title={state.title}
        message={state.message}
        confirmLabel={state.confirmLabel}
        cancelLabel={state.cancelLabel}
        destructive={state.destructive}
        onConfirm={state.onConfirm}
        onClose={close}
      />
    </AdminLayout>
  );
}
