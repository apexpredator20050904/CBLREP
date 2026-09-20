// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Exchanges console (/admin/exchanges)
// Lists all member exchanges (freecycling, bartering, lending, timebank)
// from the admin read model: GET /admin/exchanges?type=…
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import {
  EmptyRow,
  FilterBar,
  StatusBadge,
  TableCard,
  selectClass,
  tableClass,
  tdClass,
  tdStrongClass,
  thClass,
  theadClass,
} from "../components/ui";
import { api } from "../services/adminApi";

const TYPES = ["all", "freecycling", "bartering", "lending", "timebank"];

const toneFor = (s) => {
  const v = String(s || "").toLowerCase();
  if (v.includes("complet")) return "success";
  if (v.includes("disput") || v.includes("cancel")) return "danger";
  if (v.includes("pend") || v.includes("negot")) return "warn";
  return "default";
};

export default function ExchangesPage() {
  const [type, setType] = useState("all");
  const [exchanges, setExchanges] = useState([]);
  const [toast, setToast] = useState("");

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/admin/exchanges", {
        params: type === "all" ? {} : { type },
      });
      setExchanges(data.exchanges || data || []);
    } catch (e) {
      flash(e?.response?.data?.message || "Failed to load exchanges.");
    }
  }, [type]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  return (
    <AdminLayout title="Exchange Management" toast={toast}>
      <FilterBar count={`${exchanges.length} exchange(s)`}>
        <select value={type} onChange={(e) => setType(e.target.value)} className={selectClass}>
          {TYPES.map((t) => (
            <option key={t} value={t}>{t === "all" ? "All types" : t}</option>
          ))}
        </select>
      </FilterBar>

      <TableCard title="Member exchanges">
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              <th className={thClass}>Listing</th>
              <th className={thClass}>Type</th>
              <th className={thClass}>Parties</th>
              <th className={thClass}>Status</th>
              <th className={thClass}>Updated</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {exchanges.length === 0 ? (
              <EmptyRow colSpan={5}>No exchanges recorded yet.</EmptyRow>
            ) : (
              exchanges.map((x) => (
                <tr key={x.id} className="hover:bg-stone-50">
                  <td className={tdStrongClass}>{x.listing_title || x.resource_title || `#${x.id}`}</td>
                  <td className={tdClass}>{x.type || "—"}</td>
                  <td className={tdClass}>{[x.requester_name, x.owner_name].filter(Boolean).join(" ⇄ ") || "—"}</td>
                  <td className={tdClass}>
                    <StatusBadge tone={toneFor(x.status)}>{x.status || "—"}</StatusBadge>
                  </td>
                  <td className={tdClass}>{x.updated_at || x.created_at || "—"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </TableCard>
    </AdminLayout>
  );
}
