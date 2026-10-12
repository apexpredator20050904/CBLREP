// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Barter Requests — manage live trade negotiations
// ─────────────────────────────────────────────────────────────
// Mirrors the mobile Barter Inbox: incoming/outgoing proposals from
// GET /api/barter-proposals with inline Accept / Decline / Complete
// actions (PATCH /api/barter-proposals/{id}/status). State updates are
// applied in place — no full page reload.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { fetchBarterProposals, updateBarterStatus } from "../services/adminApi";
import { useAutoRefresh } from "../hooks/useAutoRefresh";

const STATUS_STYLES = {
  Pending: "bg-amber-100 text-amber-800",
  Accepted: "bg-blue-100 text-blue-800",
  Rejected: "bg-red-100 text-red-800",
  Completed: "bg-emerald-100 text-emerald-800",
};

function StatusBadge({ status }) {
  return (
    <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide ${STATUS_STYLES[status] || "bg-stone-100 text-stone-600"}`}>
      {status}
    </span>
  );
}

function ItemChip({ item, label }) {
  if (!item) return <span className="text-xs text-stone-400">—</span>;
  return (
    <div className="flex items-center gap-2">
      {item.image_url ? (
        <img src={item.image_url} alt="" className="h-9 w-9 rounded-lg object-cover" />
      ) : (
        <span className="grid h-9 w-9 place-items-center rounded-lg bg-emerald-50 text-xs">📦</span>
      )}
      <div>
        <p className="text-[10px] uppercase tracking-wide text-stone-400">{label}</p>
        <p className="text-xs font-semibold text-stone-800">{item.title}</p>
      </div>
    </div>
  );
}

export default function BarterRequestsPage() {
  const [data, setData] = useState(null);
  const [tab, setTab] = useState("incoming");
  const [error, setError] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const load = useCallback(async () => {
    try {
      setData(await fetchBarterProposals());
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    // `load()` is awaited inside the effect instead of being called straight
    // away: the state updates then land in a promise callback rather than
    // synchronously in the effect body (the cascading-render pattern the lint
    // rule flags).
    void (async () => {
      await load();
    })();
  }, [load]);

  // Keep the proposal queue live as other members respond.
  useAutoRefresh(load, 15000);

  const act = async (id, status) => {
    setBusyId(id);
    try {
      const res = await updateBarterStatus(id, status);
      // Patch the proposal in place — no reload.
      setData((current) => {
        if (!current) return current;
        const patch = (list) => list.map((p) => (p.id === id ? { ...p, status: res.proposal.status, raw_status: res.proposal.raw_status } : p));
        return { ...current, incoming: patch(current.incoming), outgoing: patch(current.outgoing) };
      });
    } catch (e) {
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const rows = tab === "incoming" ? data?.incoming ?? [] : data?.outgoing ?? [];

  return (
    <AdminLayout title="Barter Requests">
      <div className="space-y-4">
        <div className="flex gap-2">
          {["incoming", "outgoing"].map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold transition ${tab === t ? "bg-emerald-900 text-white" : "bg-stone-100 text-stone-600 hover:bg-stone-200"}`}
            >
              {t === "incoming" ? "Incoming" : "Outgoing"} ({t === "incoming" ? data?.incoming?.length ?? 0 : data?.outgoing?.length ?? 0})
            </button>
          ))}
        </div>

        {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

        {!data ? (
          <p className="text-sm text-stone-500">Loading barter requests…</p>
        ) : rows.length === 0 ? (
          <p className="rounded-xl border border-dashed border-stone-300 bg-white p-6 text-center text-sm text-stone-400">
            No {tab} barter requests right now.
          </p>
        ) : (
          <div className="space-y-3">
            {rows.map((p) => (
              <div key={p.id} className="rounded-2xl border border-stone-200 bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-xs text-stone-500">
                    {tab === "incoming" ? `From ${p.counterparty}` : `To ${p.counterparty}`} · {p.created_at}
                  </p>
                  <StatusBadge status={p.status} />
                </div>

                <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <ItemChip item={p.offered_item} label="Offers" />
                  <ItemChip item={p.requested_item} label="Wants in return" />
                </div>

                <div className="mt-4 flex flex-wrap gap-2">
                  {tab === "incoming" && p.raw_status === "pending" && (
                    <>
                      <button disabled={busyId === p.id} onClick={() => act(p.id, "accepted")} className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
                        Accept
                      </button>
                      <button disabled={busyId === p.id} onClick={() => act(p.id, "rejected")} className="rounded-lg bg-red-100 px-3 py-1.5 text-xs font-semibold text-red-700 disabled:opacity-50">
                        Decline
                      </button>
                    </>
                  )}
                  {p.raw_status === "accepted" && (
                    <button disabled={busyId === p.id} onClick={() => act(p.id, "completed")} className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
                      Mark Completed
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </AdminLayout>
  );
}
