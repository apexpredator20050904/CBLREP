// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Listing moderation (/admin/listings*)
// Review Offers & Needs posts: approve, flag, hide, remove (with reason),
// restore. `kind` comes from the route: all | offers | needs | flagged.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import AdminLayout from "../components/AdminLayout";
import ConfirmModal from "../components/ConfirmModal";
import { useConfirm } from "../components/useConfirm";
import DataTable from "../components/DataTable";
import {
  StatusBadge,
  CompensationBadge,
  listingTone,
  tableActionBtn,
  tableActionDanger,
  tableActionWarn,
} from "../components/ui";
import { fetchListings, moderateListing } from "../services/adminApi";

const TITLES = {
  all: "All Listings",
  offers: "Offers",
  needs: "Needs",
  flagged: "Flagged Resources",
};

export default function ListingsPage({ kind = "all" }) {
  const [resources, setResources] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState("");
  const [busyId, setBusyId] = useState(null);
  const { close, setConfirm, state } = useConfirm();

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      setLoading(true);
      setResources(await fetchListings(kind));
    } catch (e) {
      flash(e.message);
    } finally {
      setLoading(false);
    }
  }, [kind]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  const moderate = (r, action) => {
    let reason = "";
    if (["remove", "hide"].includes(action)) {
      reason = window.prompt(`Reason for ${action}ing "${r.title}"? (required)`) || "";
      if (!reason.trim()) return flash("A reason is required for moderation actions.");
    }
    const label = action === "hide" ? "hidden" : action === "restore" ? "restored" : action;
    setConfirm({
      title: `Listing "${r.title}" — ${action}d?`,
      message:
        action === "remove"
          ? `Permanently delete "${r.title}"? Members will no longer see it. Reason: "${reason.trim()}".`
          : action === "hide"
          ? `Hide "${r.title}" from public view? Reason: "${reason.trim()}". It can be restored later.`
          : action === "restore"
          ? `Restore "${r.title}" so it is visible again?`
          : action === "flag"
          ? `Flag "${r.title}" for admin review?`
          : `Mark "${r.title}" as ${label}?`,
      confirmLabel: `Confirm ${action}`,
      destructive: ["remove", "hide"].includes(action),
      onConfirm: async () => {
        setBusyId(r.id);
        try {
          await moderateListing(r.id, action, reason.trim());
          flash(`Listing ${action}d.`);
          load();
        } catch (e) {
          flash(e.message);
        } finally {
          setBusyId(null);
        }
      },
    });
  };

  const columns = [
    {
      key: "image_url",
      label: "Photo",
      sortable: false,
      render: (r) =>
        r.image_url ? (
          <img
            src={r.image_url}
            alt={r.title || "Listing photo"}
            className="w-14 h-14 object-cover rounded-md border border-gray-200 bg-gray-100"
            onError={(e) => { e.currentTarget.style.display = "none"; }}
          />
        ) : (
          <div className="w-14 h-14 rounded-md border border-gray-200 bg-gray-100 flex items-center justify-center text-gray-400 text-xs">
            No photo
          </div>
        ),
    },
    {
      key: "title",
      label: "Listing",
      sortable: true,
      filter: { type: "text" },
      strong: true,
      getValue: (r) => r.title || "",
      render: (r) => (
        <span className="block text-xs leading-tight">
          <span className="block font-semibold text-emerald-950">{r.title}</span>
          {/* A NEED can say how much it needs ("5 kg of rice"). */}
          {r.quantity ? (
            <span className="block text-[11px] text-stone-500">
              Needs: {r.quantity}
            </span>
          ) : null}
        </span>
      ),
    },
    {
      key: "type",
      label: "Type",
      sortable: true,
      filter: {
        type: "select",
        options: [
          { value: "Offer", label: "Offer" },
          { value: "Need", label: "Need" },
        ],
      },
    },
    {
      key: "compensation",
      label: "Compensation",
      sortable: false,
      render: (r) => (
        <CompensationBadge
          type={r.compensation_type}
          label={r.compensation_label}
          price={r.price}
          budget={r.price_role === "budget"}
        />
      ),
      // DataTable filters match on the accessor value; expose the raw key so
      // the select offers FREE SHARING / BARTER / PAID.
      getValue: (r) => r.compensation_type,
      filter: {
        type: "select",
        options: [
          { value: "free", label: "FREE SHARING" },
          { value: "barter", label: "BARTER" },
          { value: "paid", label: "PAID" },
        ],
      },
    },
    { key: "category", label: "Category", filter: { type: "text" } },
    {
      key: "location",
      label: "Barangay · Purok",
      sortable: false,
      getValue: (r) => [r.barangay, r.purok_sitio].filter(Boolean).join(" "),
      render: (r) => (
        <span className="text-xs whitespace-nowrap">
          {r.barangay || "—"}
          {r.purok_sitio ? ` · ${r.purok_sitio}` : ""}
        </span>
      ),
      filter: { type: "text" },
    },
    { key: "owner", label: "Owner", filter: { type: "text" } },
    {
      key: "admin_status",
      label: "Status",
      sortable: true,
      render: (r) => <StatusBadge tone={listingTone(r.admin_status)}>{r.admin_status}</StatusBadge>,
      filter: {
        type: "select",
        options: [
          { value: "Active", label: "Active" },
          { value: "Pending", label: "Pending" },
          { value: "Flagged", label: "Flagged" },
          { value: "Hidden", label: "Hidden" },
          { value: "Removed", label: "Removed" },
        ],
      },
    },
    { key: "created_at", label: "Posted" },
    {
      key: "actions",
      label: "Moderation",
      render: (r) => (
        <div className="flex flex-wrap gap-1.5">
          <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "approve")} className={tableActionBtn}>Approve</button>
          <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "flag")} className={tableActionWarn}>Flag</button>
          <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "remove")} className={tableActionDanger}>Remove</button>
          {(r.status === "removed" || r.status === "hidden") && (
            <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "restore")} className={tableActionBtn}>Restore</button>
          )}
        </div>
      ),
    },
  ];

  return (
    <AdminLayout title={TITLES[kind] || "Resource Management"} toast={toast}>
      <DataTable
        columns={columns}
        rows={resources}
        loading={loading}
        emptyMessage="No listings in this view."
        initialSort={{ key: "title", dir: "asc" }}
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

