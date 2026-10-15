// ─────────────────────────────────────────────────────────────
// CBLRE Admin · User & role management (/admin/accounts)
// Full CRUD over user/admin accounts backed by /admin/accounts.
// RBAC: role changes + deletions are Super-Admin-only (hidden in the UI
// and enforced again server-side by the super.admin middleware).
// Uses the shared DataTable (per-column filters, sort, pagination).
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import ConfirmModal from "../components/ConfirmModal";
import { useConfirm } from "../components/useConfirm";
import DataTable from "../components/DataTable";
import { PageHeader, StatusBadge, UserAvatar, btnPrimary, tableActionBtn, tableActionDanger } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { TRINIDAD_BARANGAYS } from "../config/community";
import {
  createAccount,
  deleteAccount,
  fetchAccounts,
  updateAccount,
  updateAccountRole,
} from "../services/adminApi";

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

const statusTone = (s) => (s === "suspended" ? "danger" : s === "pending" ? "warn" : "success");

export default function AdminAccountsPage() {
  const { user: me } = useAuth();
  const isSuper = String(me?.raw_role || "") === "super_admin";

  const [rows, setRows] = useState([]);
  const [meta, setMeta] = useState({ current_page: 1, total: 0, last_page: 1 });
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState("");
  const [modal, setModal] = useState(null); // { mode: "create"|"edit", user }
  const [form, setForm] = useState(EMPTY_FORM);
  const [fieldErrors, setFieldErrors] = useState({});
  const [busy, setBusy] = useState(false);
  const [query, setQuery] = useState({ page: 1, per_page: 10 });
  const { close, setConfirm, state } = useConfirm();

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(
    async (params = query) => {
      setLoading(true);
      try {
        const { rows: data, meta: m } = await fetchAccounts(params);
        setRows(data);
        setMeta(m);
      } catch (e) {
        flash(e.message);
        setRows([]);
      } finally {
        setLoading(false);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [query.page, query.per_page],
  );

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query.page, query.per_page]);
  useAutoRefresh(load, 15000);

  const handleQuery = (q) => {
    // DataTable emits { q, filters, sort_by, sort_dir, page, per_page }.
    setQuery((prev) => ({ ...prev, ...q, page: q.page ?? 1 }));
    // Debounced-ish: run immediately; Laravel LIKE filters are cheap here.
    load({ ...query, ...q, page: q.page ?? 1 });
  };

  // ── CRUD handlers ──────────────────────────────────────────────────
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
  const toggleStatus = (u) => {
    const nextStatus = u.account_status === "suspended" ? "active" : "suspended";
    setConfirm({
      title: nextStatus === "suspended" ? "Suspend account?" : "Reactivate account?",
      message: nextStatus === "suspended"
        ? `Suspend ${u.name}? They will no longer be able to log in until reactivated.`
        : `Reactivate ${u.name}? They will regain full access to their account.`,
      confirmLabel: nextStatus === "suspended" ? "Suspend" : "Reactivate",
      destructive: nextStatus === "suspended",
      onConfirm: async () => {
        try {
          await updateAccount(u.id, { account_status: nextStatus });
          flash(nextStatus === "suspended" ? "Account suspended." : "Account reactivated.");
          load();
        } catch (err) {
          flash(err.message);
        }
      },
    });
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
          <UserAvatar name={u.name} url={u.avatar_url} size={32} />
          <div>
            <p>{u.name}{u.id === me?.id ? " (you)" : ""}</p>
            {u.student_status ? (
              <p className="text-xs text-sky-700">🎓 {u.student_school || "Student"}</p>
            ) : null}
          </div>
        </div>
      ),
    },
    { key: "email", label: "Email", sortable: true, filter: { type: "text" } },
    {
      key: "raw_role",
      label: "Role",
      sortable: true,
      getValue: (u) => u.role,
      filter: { type: "select", options: ROLE_OPTIONS },
    },
    {
      key: "verification_status",
      label: "Verification",
      sortable: true,
      render: (u) => (
        <StatusBadge tone={u.verification_status === "verified" ? "success" : "warn"}>
          {u.verification_status}
        </StatusBadge>
      ),
      filter: {
        type: "select",
        options: [
          { value: "verified", label: "Verified" },
          { value: "pending", label: "Pending" },
          { value: "rejected", label: "Rejected" },
          { value: "unverified", label: "Unverified" },
        ],
      },
    },
    {
      key: "account_status",
      label: "Account",
      sortable: true,
      render: (u) => (
        <StatusBadge tone={statusTone(u.account_status)}>{u.account_status}</StatusBadge>
      ),
      filter: {
        type: "select",
        options: [
          { value: "active", label: "Active" },
          { value: "suspended", label: "Suspended" },
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
          <button type="button" onClick={() => openEdit(u)} className={tableActionBtn}>Edit</button>
          {isSuper && u.id !== me?.id && (
            <>
              <button type="button" onClick={() => changeRole(u)} className={tableActionBtn}>Role</button>
              <button type="button" onClick={() => remove(u)} className={tableActionDanger}>Delete</button>
            </>
          )}
          {u.id !== me?.id && (isSuper || u.raw_role === "user") && (
            <button type="button" onClick={() => toggleStatus(u)} className={tableActionBtn}>
              {u.account_status === "suspended" ? "Reactivate" : "Suspend"}
            </button>
          )}
        </div>
      ),
    },
  ];

  const err = (k) =>
    fieldErrors[k] ? <p className="mt-1 text-xs text-red-600">{fieldErrors[k][0]}</p> : null;

  return (
    <AdminLayout title="User & Role Management" toast={toast}>
      <PageHeader
        title="Accounts"
        subtitle={
          isSuper
            ? "Create, edit and delete member/administrator accounts. Every change is audit-logged."
            : "Manage member accounts. Role changes and deletions require a Super Administrator."
        }
        actions={
          <button type="button" onClick={openCreate} className={btnPrimary}>+ Add account</button>
        }
      />

      <DataTable
        columns={columns}
        rows={rows}
        loading={loading}
        emptyMessage="No accounts match the current filters."
        serverMode
        page={meta.current_page || query.page}
        totalCount={meta.total}
        onQueryChange={handleQuery}
        initialSort={{ key: "created_at", dir: "desc" }}
      />

      {/* Create / Edit modal */}
      {modal ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          onClick={() => !busy && setModal(null)}
        >
          <form
            onSubmit={submit}
            onClick={(e) => e.stopPropagation()}
            className="max-h-[90vh] w-full max-w-lg space-y-3 overflow-y-auto rounded-2xl bg-white p-6 shadow-xl"
          >
            <h3 className="text-lg font-bold text-emerald-950">
              {modal.mode === "create" ? "New account" : `Edit — ${modal.user.name}`}
            </h3>

            <label className="block text-sm">
              <span className="font-semibold text-stone-700">Full name</span>
              <input
                required
                value={form.name}
                onChange={(e) => setField("name", e.target.value)}
                className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              />
              {err("name")}
            </label>

            <label className="block text-sm">
              <span className="font-semibold text-stone-700">Email</span>
              <input
                required
                type="email"
                value={form.email}
                onChange={(e) => setField("email", e.target.value)}
                className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              />
              {err("email")}
            </label>

            {isSuper ? (
              <label className="block text-sm">
                <span className="font-semibold text-stone-700">Role</span>
                <select
                  value={form.role}
                  onChange={(e) => setField("role", e.target.value)}
                  disabled={modal.mode === "edit" && modal.user.id === me?.id}
                  className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none disabled:bg-stone-100"
                >
                  {ROLE_OPTIONS.map((r) => (
                    <option key={r.value} value={r.value}>{r.label}</option>
                  ))}
                </select>
                {err("role")}
              </label>
            ) : null}

            <label className="block text-sm">
              <span className="font-semibold text-stone-700">
                {modal.mode === "create" ? "Password" : "New password (leave blank to keep)"}
              </span>
              <input
                required={modal.mode === "create"}
                type="password"
                minLength={modal.mode === "create" || form.password ? 8 : undefined}
                value={form.password}
                onChange={(e) => setField("password", e.target.value)}
                autoComplete="new-password"
                className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
              />
              {err("password")}
            </label>

            {modal.mode === "create" || form.password ? (
              <label className="block text-sm">
                <span className="font-semibold text-stone-700">Confirm password</span>
                <input
                  required={modal.mode === "create" || !!form.password}
                  type="password"
                  value={form.password_confirmation}
                  onChange={(e) => setField("password_confirmation", e.target.value)}
                  autoComplete="new-password"
                  className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                />
                {err("password_confirmation")}
              </label>
            ) : null}

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
