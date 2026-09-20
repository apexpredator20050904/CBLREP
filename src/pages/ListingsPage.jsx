// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Listing moderation (/admin/listings*)
// Review Offers & Needs posts: approve, flag, hide, remove (with reason),
// restore. `kind` comes from the route: all | offers | needs | flagged.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  FilterBar,
  StatusBadge,
  TableCard,
  listingTone,
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
import { fetchListings, moderateListing } from "../services/adminApi";

const TITLES = {
  all: "All Listings",
  offers: "Offers",
  needs: "Needs",
  flagged: "Flagged Resources",
};

export default function ListingsPage({ kind = "all" }) {
  const [resources, setResources] = useState([]);
  const [category, setCategory] = useState("all");
  const [toast, setToast] = useState("");
  const [busyId, setBusyId] = useState(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      setResources(await fetchListings(kind));
    } catch (e) {
      flash(e.message);
    }
  }, [kind]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCategory("all");
    load();
  }, [load]);

  const moderate = async (r, action) => {
    let reason = "";
    if (["remove", "hide"].includes(action)) {
      reason = window.prompt(`Reason for ${action}ing "${r.title}"? (required)`) || "";
      if (!reason.trim()) return flash("A reason is required for moderation actions.");
    }
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
  };

  const cats = ["all", ...new Set(resources.map((r) => r.category).filter(Boolean))];
  const visible = category === "all" ? resources : resources.filter((r) => r.category === category);

  return (
    <AdminLayout title={TITLES[kind] || "Resource Management"} toast={toast}>
      <FilterBar count={`${visible.length} listing(s)`}>
        <select value={category} onChange={(e) => setCategory(e.target.value)} className={selectClass}>
          {cats.map((c) => (
            <option key={c} value={c}>{c === "all" ? "All categories" : c}</option>
          ))}
        </select>
      </FilterBar>

      <TableCard>
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Listing</th>
              <th className={thClass}>Type</th>
              <th className={thClass}>Owner</th>
              <th className={thClass}>Status</th>
              <th className={thClass}>Moderation</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {visible.length === 0 ? (
              <EmptyRow colSpan={5}>No listings in this view.</EmptyRow>
            ) : (
              visible.map((r) => (
                <tr key={r.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{r.title}</td>
                  <td className={tdClass}>{r.type || "—"}</td>
                  <td className={tdClass}>{r.user?.name || "—"}</td>
                  <td className={tdClass}>
                    <StatusBadge tone={listingTone(r.admin_status)}>{r.admin_status}</StatusBadge>
                  </td>
                  <td className={tdClass}>
                    <div className="flex flex-wrap gap-1.5">
                      <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "approve")} className={tableActionBtn}>Approve</button>
                      <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "flag")} className={tableActionWarn}>Flag</button>
                      <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "remove")} className={tableActionDanger}>Remove</button>
                      {(r.status === "removed" || r.status === "hidden") && (
                        <button type="button" disabled={busyId === r.id} onClick={() => moderate(r, "restore")} className={tableActionBtn}>Restore</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>
    </AdminLayout>
  );
}
