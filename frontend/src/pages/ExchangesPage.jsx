// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Barter Exchange console (/admin/exchanges)
//
// Direct bartering only. Every row is a two-way proposal: one member
// asks to trade for another's listing and names what they give back.
//   Proposer (receiver) → Owner (provider)
//
// DUAL-CONFIRMATION MODEL: completion is member-driven ONLY. Both parties
// confirm independently on the mobile app (POST /exchanges/{id}/
// confirm-completion); the row flips to `completed` once both flags are
// set. The console is READ-ONLY for completion — it renders the
// proposer/owner confirmation progress instead of a "Complete" button.
//
// Admin actions map onto the server-side state machine in
// App\Models\Exchange::TRANSITIONS — the console never invents a
// transition the members themselves could not make:
//   Pending  → Approve · Decline · Cancel
//   Accepted → Cancel (+ read-only dual-confirmation progress)
// Completed / Declined / Cancelled are terminal.
//
// Every action is validated, audit-logged and notifies both parties
// server-side (AdminApprovalController::approveExchange).
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import ConfirmModal from "../components/ConfirmModal";
import { useConfirm } from "../components/useConfirm";
import DataTable from "../components/DataTable";
import { StatusBadge, selectClass } from "../components/ui";
import { api, approveExchange } from "../services/adminApi";

/**
 * Status filter values. The value is what goes on the wire; the label is
 * what the panel reads. `active` is retained as the API's own vocabulary
 * for an agreed trade (AdminPortalController::$statusMap maps it to
 * `accepted`), so the select cannot drift from the backend contract.
 */
const STATUSES = [
  { value: "all", label: "All statuses" },
  { value: "pending", label: "Pending" },
  { value: "active", label: "Accepted" },
  { value: "completed", label: "Completed" },
  { value: "rejected", label: "Declined" },
  { value: "cancel", label: "Cancelled" },
];

const STATUS_LABELS = {
  pending: "Pending",
  accepted: "Accepted",
  completed: "Completed",
  rejected: "Declined",
  cancelled: "Cancelled",
  approved: "Accepted",
};

const toneFor = (raw) => {
  const v = String(raw || "").toLowerCase();
  if (v === "completed") return "success";
  if (v === "accepted" || v === "approved") return "info";
  if (v === "rejected" || v === "cancelled") return "danger";
  if (v === "pending") return "warn";
  return "default";
};

/**
 * The DB status of a row. `raw_status` is canonical; the display status is
 * only a fallback so an older payload without it still renders correctly.
 */
const rawOf = (x) => String(x?.raw_status || x?.status || "").toLowerCase();

const statusLabel = (raw) => STATUS_LABELS[raw] || raw || "—";

/**
 * Admin actions available per status — the client-side mirror of
 * Exchange::TRANSITIONS, minus completion.
 *
 * Dual-confirmation: `completed` is deliberately NOT an admin action —
 * only the two members can complete a trade (both confirm via the mobile
 * app). The console shows a read-only progress indicator instead.
 * This is a UX affordance only: the server re-validates every transition,
 * so a stale button here cannot corrupt data.
 */
const actionsFor = (raw) => {
  switch (String(raw || "").toLowerCase()) {
    case "pending":
      return ["approved", "rejected", "cancelled"];
    case "accepted":
    case "approved":
      return ["cancelled"];
    default:
      return []; // terminal — nothing to do
  }
};

/** Read-only dual-confirmation progress for an accepted/completed row. */
const confirmationOf = (x) => {
  const proposer = x?.proposer_confirmed === true;
  const owner = x?.owner_confirmed === true;
  const label =
    x?.confirmation_label ||
    (proposer && owner
      ? "Both confirmed — Exchange completed"
      : proposer || owner
        ? "Waiting for other party's confirmation"
        : "Awaiting both confirmations");
  return { proposer, owner, label };
};

export default function ExchangesPage() {
  const [status, setStatus] = useState("all");
  const [exchanges, setExchanges] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState("");

  const { close, setConfirm, state } = useConfirm();
  const [busyId, setBusyId] = useState(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  // Unwrap whatever shape Laravel sends back:
  //   { exchanges: [...] }            → admin read model (AdminPortalController)
  //   { data: [...], ... }            → paginated response (response.data.data)
  //   [...]                           → plain array fallback
  const unwrap = (payload) => {
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload?.exchanges)) return payload.exchanges;
    if (Array.isArray(payload?.data?.data)) return payload.data.data; // paginator
    if (Array.isArray(payload?.data)) return payload.data;
    return [];
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await api.get("/admin/exchanges", {
        params: status === "all" ? {} : { status },
      });
      setExchanges(unwrap(data));
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load barter exchanges.");
      setExchanges([]);
    } finally {
      setLoading(false);
    }
  }, [status]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  // ── Approval workflow actions (server validates + audit-logs) ────
  const decide = (x, nextStatus) => {
    const label = statusLabel(nextStatus);

    // Declining and cancelling are both consequential for the members, so
    // both demand a written justification — it lands in the audit log and is
    // what a panel member can read back if a decision is challenged.
    const needsReason = nextStatus === "rejected" || nextStatus === "cancelled";
    let reason = "";
    if (needsReason) {
      const prompt = nextStatus === "rejected"
        ? `Reason for declining barter ${x.transaction_id || `#${x.id}`}? (required)`
        : `Reason for cancelling barter ${x.transaction_id || `#${x.id}`}? (required)`;
      reason = window.prompt(prompt) || "";
      if (!reason.trim()) return flash("A reason is required to close a barter.");
    }

    setConfirm({
      title: `${x.transaction_id || `Exchange #${x.id}`} — mark ${label}?`,
      message: needsReason
        ? `${tradeSummary(x)} will be marked "${label}". Reason: "${reason.trim()}". Both members are notified.`
        : `${tradeSummary(x)} will be marked "${label}". Both members are notified.`,
      confirmLabel: `Confirm ${label}`,
      destructive: needsReason,
      onConfirm: async () => {
        setBusyId(x.id);
        try {
          await approveExchange(x.id, nextStatus, reason.trim());
          flash(`Barter ${label.toLowerCase()}.`);
          load();
        } catch (e) {
          // 422s from the transition guard carry the allowed set — surface
          // the server's wording rather than a generic failure.
          flash(e.message);
        } finally {
          setBusyId(null);
        }
      },
    });
  };

  const formatDate = (v) => {
    if (!v) return "—";
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? v : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
  };

  /** "Wanted ⇄ Offered" — the two sides of the trade, for confirm dialogs. */
  const tradeSummary = (x) =>
    `"${x.item_name || "listing"}" ⇄ "${x.offered_label || "offered item"}"`;

  const columns = [
    {
      key: "transaction_id",
      label: "Ref",
      sortable: true,
      render: (x) => (
        <span className="font-mono text-[11px] text-stone-500">
          {x.transaction_id || `EX-${String(x.id ?? "—").padStart(5, "0")}`}
        </span>
      ),
    },
    {
      // Side A — the listing the owner put up, i.e. what the proposer wants.
      key: "item_name",
      label: "Wanted",
      sortable: true,
      filter: { type: "text" },
      strong: true,
      getValue: (x) => x.item_name || x.resource || `#${x.id}`,
      render: (x) => x.item_name || x.resource || `#${x.id ?? "—"}`,
    },
    {
      // Side B — what the proposer gives back. Never blank: a missing offer
      // is a data-integrity question, and an empty cell would hide it.
      key: "offered_label",
      label: "Offered in Return",
      sortable: true,
      filter: { type: "text" },
      getValue: (x) => x.offered_label || x.offered_item || "",
      render: (x) => (
        <span className="text-xs">
          {x.offered_label || x.offered_item || "—"}
          {x.offered_resource_id ? (
            <span className="ml-1 rounded bg-stone-100 px-1 text-[10px] text-stone-500">listing</span>
          ) : (
            <span className="ml-1 rounded bg-amber-50 px-1 text-[10px] text-amber-700">skill</span>
          )}
        </span>
      ),
    },
    {
      key: "barangay",
      label: "Barangay",
      sortable: true,
      filter: { type: "text" },
      getValue: (x) => x.barangay || "",
      render: (x) => (
        <span className="text-xs">
          {x.barangay || "—"}
          {x.purok_sitio ? <span className="block text-[10px] text-stone-400">{x.purok_sitio}</span> : null}
        </span>
      ),
    },
    {
      key: "parties",
      label: "Parties",
      filter: { type: "text" },
      getValue: (x) =>
        [x.proposer_name || x.requester_name, x.owner_name].filter(Boolean).join(" ⇄ ")
          || x.users
          || [x.receiver, x.provider].filter(Boolean).join(" ⇄ "),
      render: (x) => (
        <span className="block text-xs leading-tight">
          <span className="block">
            <span className="text-stone-400">Proposer </span>
            <strong className="text-emerald-950">
              {x.proposer_name || x.requester_name || x.receiver || "—"}
            </strong>
          </span>
          <span className="block">
            <span className="text-stone-400">Owner </span>
            {x.owner_name || x.provider || "—"}
          </span>
        </span>
      ),
    },
    {
      key: "status",
      label: "Status",
      sortable: true,
      // getValue returns the same label the cell renders, so the select
      // filter compares like-for-like instead of "Declined" vs "rejected".
      getValue: (x) => statusLabel(rawOf(x)),
      render: (x) => <StatusBadge tone={toneFor(rawOf(x))}>{statusLabel(rawOf(x))}</StatusBadge>,
      filter: {
        type: "select",
        options: [
          { value: "Pending", label: "Pending" },
          { value: "Accepted", label: "Accepted" },
          { value: "Completed", label: "Completed" },
          { value: "Declined", label: "Declined" },
          { value: "Cancelled", label: "Cancelled" },
        ],
      },
    },
    {
      key: "confirmation",
      label: "Dual Confirmation",
      getValue: (x) => confirmationOf(x).label,
      render: (x) => {
        const raw = rawOf(x);
        if (raw !== "accepted" && raw !== "approved" && raw !== "completed") {
          return <span className="text-xs text-stone-400">—</span>;
        }
        const c = confirmationOf(x);
        const done = raw === "completed" || (c.proposer && c.owner);
        return (
          <span className="block text-xs leading-tight">
            <span className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold ${done ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"}`}>
              {c.label}
            </span>
            <span className="mt-1 block text-[10px] text-stone-500">
              Proposer {c.proposer ? "✓" : "·"} · Owner {c.owner ? "✓" : "·"}
            </span>
          </span>
        );
      },
    },
    {
      key: "created_at",
      label: "Initiated",
      sortable: true,
      render: (x) => (
        <span className="text-xs">
          {formatDate(x.created_at) || x.date || "—"}
          {x.updated_at && x.updated_at !== x.created_at ? (
            <span className="block text-[10px] text-stone-400">
              upd. {formatDate(x.updated_at) || x.updated_label || "—"}
            </span>
          ) : null}
        </span>
      ),
    },
    {
      key: "actions",
      label: "Action",
      render: (x) => {
        // Gate on the canonical DB status, not the display string.
        // NOTE: no "Complete" button — completion is member-driven only
        // (dual confirmation on the mobile app). Accepted rows instead
        // surface the read-only dual-confirmation progress below.
        const actions = actionsFor(rawOf(x));
        const raw = rawOf(x);
        const showProgress = raw === "accepted" || raw === "approved" || raw === "completed";
        if (actions.length === 0 && !showProgress) return <span className="text-xs text-stone-400">—</span>;
        return (
          <div className="flex flex-col gap-1.5">
          <div className="flex flex-wrap gap-1.5">
            {actions.includes("approved") && (
              <button
                type="button"
                disabled={busyId === x.id}
                onClick={() => decide(x, "approved")}
                className="rounded-md border border-emerald-300 bg-white px-2.5 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
              >
                Approve
              </button>
            )}
            {actions.includes("rejected") && (
              <button
                type="button"
                disabled={busyId === x.id}
                onClick={() => decide(x, "rejected")}
                className="rounded-md border border-amber-300 bg-white px-2.5 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-50 disabled:opacity-50"
              >
                Decline
              </button>
            )}
            {actions.includes("cancelled") && (
              <button
                type="button"
                disabled={busyId === x.id}
                onClick={() => decide(x, "cancelled")}
                className="rounded-md border border-red-200 bg-white px-2.5 py-1 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-50"
              >
                Cancel
              </button>
            )}
          </div>
          {showProgress && (
            <span className="text-[10px italic] text-stone-500">
              Member completion only — {confirmationOf(x).label} (Proposer {confirmationOf(x).proposer ? "✓" : "·"} · Owner {confirmationOf(x).owner ? "✓" : "·"})
            </span>
          )}
          </div>
        );
      },
    },
  ];

  return (
    <AdminLayout title="Barter Management" toast={toast}>
      <div className="mb-4 rounded-xl border border-emerald-200 bg-emerald-50/60 p-3 text-xs text-emerald-950">
        Direct bartering only — every row is a two-way proposal where a member
        offers something in return. Completion is member-driven: both the
        proposer and the owner must confirm the handover on the mobile app
        before a trade becomes completed. Admins cannot complete trades.
      </div>

      <div className="flex flex-wrap items-center gap-2 rounded-xl border border-stone-200 bg-white p-3 shadow-sm">
        <select value={status} onChange={(e) => setStatus(e.target.value)} className={selectClass}>
          {STATUSES.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
        <button
          type="button"
          onClick={load}
          disabled={loading}
          className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-semibold text-emerald-950 hover:bg-stone-50 disabled:opacity-50"
        >
          {loading ? "Refreshing…" : "Refresh"}
        </button>
        <span className="ml-auto text-xs text-stone-500">
          {exchanges.length} barter proposal{exchanges.length === 1 ? "" : "s"}
        </span>
      </div>

      <DataTable
        columns={columns}
        rows={exchanges}
        loading={loading}
        emptyMessage="No barter proposals yet. Members can propose a trade from any listing."
        initialSort={{ key: "created_at", dir: "desc" }}
        rowKey={(x) => x.id ?? x.transaction_id}
      />
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
