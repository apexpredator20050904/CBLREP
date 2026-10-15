// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Direct Inquiries (/admin/inquiries)
// ─────────────────────────────────────────────────────────────
// Members negotiate free / barter / paid exchanges with each other in the
// Flutter app. This screen gives moderators read access to every
// listing-scoped conversation plus an official reply box, so the council can
// answer questions and de-escalate disputes. The thread polls on a timer, so
// replies appear without a page refresh.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useRef, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { CompensationBadge, StatusBadge, btnPrimary } from "../components/ui";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import { fetchInquiries, fetchInquiry, replyToInquiry } from "../services/adminApi";

const initials = (name) =>
  (name || "?")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join("")
    .toUpperCase();

const whenLabel = (iso) => {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const diff = Date.now() - d.getTime();
  const mins = Math.round(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  if (mins < 1440) return `${Math.round(mins / 60)}h ago`;
  return d.toLocaleDateString();
};

export default function InquiriesPage() {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [toast, setToast] = useState("");

  const [activeId, setActiveId] = useState(null);
  const [thread, setThread] = useState(null); // { inquiry, messages }
  const [threadLoading, setThreadLoading] = useState(false);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const threadEndRef = useRef(null);

  const flash = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  };

  const load = useCallback(
    async ({ silent = false } = {}) => {
      try {
        if (!silent) setLoading(true);
        const data = await fetchInquiries({ q: search });
        setRows(data);
      } catch (e) {
        if (!silent) flash(e.message);
      } finally {
        if (!silent) setLoading(false);
      }
    },
    [search],
  );

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(() => load({ silent: true }), 8000);

  const openThread = useCallback(async ({ silent = false } = {}) => {
    if (!activeId) return;
    try {
      if (!silent) setThreadLoading(true);
      const data = await fetchInquiry(activeId);
      setThread(data);
      if (!silent) setRows((prev) => prev);
    } catch (e) {
      if (!silent) flash(e.message);
    } finally {
      if (!silent) setThreadLoading(false);
    }
  }, [activeId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    openThread();
  }, [openThread]);
  useAutoRefresh(() => openThread({ silent: true }), 6000);

  useEffect(() => {
    threadEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [thread?.messages?.length, activeId]);

  const send = async () => {
    const body = draft.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      await replyToInquiry(activeId, body);
      setDraft("");
      flash("Reply sent to both members.");
      await openThread({ silent: true });
      await load({ silent: true });
    } catch (e) {
      flash(e.message);
    } finally {
      setSending(false);
    }
  };

  return (
    <AdminLayout
      title="Direct Inquiries"
      subtitle="Read and moderate member conversations about community listings"
      toast={toast}
    >
      <div className="grid gap-4 lg:grid-cols-[340px_1fr]">
        {/* ── Inbox list ─────────────────────────────────────── */}
        <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
          <div className="border-b border-stone-100 p-3">
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search listing, buyer or seller…"
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
            />
          </div>
          <div className="max-h-[70vh] overflow-y-auto">
            {loading ? (
              <p className="px-4 py-8 text-center text-sm text-stone-500">Loading…</p>
            ) : rows.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-stone-500">
                No inquiries yet. Members start them from a listing in the app.
              </p>
            ) : (
              rows.map((r) => {
                const active = r.id === activeId;
                return (
                  <button
                    key={r.id}
                    type="button"
                    onClick={() => setActiveId(r.id)}
                    className={`flex w-full items-start gap-3 border-b border-stone-100 px-4 py-3 text-left transition hover:bg-stone-50 ${
                      active ? "bg-emerald-50/70" : ""
                    }`}
                  >
                    <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-emerald-800 text-xs font-bold text-white">
                      {initials(r.buyer?.name)}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center justify-between gap-2">
                        <span className="truncate text-sm font-semibold text-emerald-950">
                          {r.buyer?.name || "Member"}
                        </span>
                        <span className="shrink-0 text-[10px] text-stone-400">
                          {whenLabel(r.last_message_at || r.updated_at)}
                        </span>
                      </span>
                      <span className="mt-1 block truncate text-xs text-stone-500">
                        {r.listing?.title || "Listing removed"}
                      </span>
                      <span className="mt-1 flex items-center gap-2">
                        {r.listing && (
                          <CompensationBadge
                            type={r.listing.compensation_type}
                            label={r.listing.compensation_label}
                            price={r.listing.price}
                          />
                        )}
                        <span className="text-[10px] text-stone-400">
                          {r.message_count} msg
                        </span>
                      </span>
                    </span>
                  </button>
                );
              })
            )}
          </div>
        </div>

        {/* ── Thread ─────────────────────────────────────────── */}
        <div className="flex min-h-[70vh] flex-col overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
          {!activeId ? (
            <div className="flex flex-1 items-center justify-center p-8 text-center text-sm text-stone-500">
              Select an inquiry to read the conversation.
            </div>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-3 border-b border-stone-100 px-5 py-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-bold text-emerald-950">
                    {thread?.inquiry?.listing?.title || "Listing"}
                  </p>
                  <p className="text-xs text-stone-500">
                    {thread?.inquiry?.buyer?.name || "Member"} → {thread?.inquiry?.seller?.name || "Owner"}
                  </p>
                </div>
                {thread?.inquiry?.listing && (
                  <span className="ml-auto">
                    <CompensationBadge
                      type={thread.inquiry.listing.compensation_type}
                      label={thread.inquiry.listing.compensation_label}
                      price={thread.inquiry.listing.price}
                    />
                  </span>
                )}
                <StatusBadge tone="info">Inquiry</StatusBadge>
              </div>

              <div className="flex-1 space-y-3 overflow-y-auto bg-stone-50/60 p-5">
                {threadLoading && !thread ? (
                  <p className="text-center text-sm text-stone-500">Loading…</p>
                ) : (thread?.messages || []).length === 0 ? (
                  <p className="text-center text-sm text-stone-500">No messages yet.</p>
                ) : (
                  (thread?.messages || []).map((m) => {
                    const isAdmin = m.sender?.id === 1 || m.is_admin;
                    return (
                      <div key={m.id} className="rounded-xl border border-stone-200 bg-white p-3">
                        <div className="mb-1 flex items-center justify-between gap-2">
                          <span className="text-xs font-bold text-emerald-950">
                            {m.sender?.name || "Member"}
                            {isAdmin ? " · Admin" : ""}
                          </span>
                          <span className="text-[10px] text-stone-400">{whenLabel(m.created_at)}</span>
                        </div>
                        <p className="whitespace-pre-wrap text-sm text-stone-700">{m.body}</p>
                      </div>
                    );
                  })
                )}
                <div ref={threadEndRef} />
              </div>

              <div className="border-t border-stone-100 p-3">
                <div className="flex items-end gap-2">
                  <textarea
                    value={draft}
                    onChange={(e) => setDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) send();
                    }}
                    rows={2}
                    placeholder="Write an official reply to both members… (Ctrl+Enter to send)"
                    className="flex-1 resize-none rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
                  />
                  <button type="button" onClick={send} disabled={sending || !draft.trim()} className={btnPrimary}>
                    {sending ? "Sending…" : "Reply"}
                  </button>
                </div>
                <p className="mt-1 text-[11px] text-stone-400">
                  Both the buyer and the listing owner receive this as a notification.
                </p>
              </div>
            </>
          )}
        </div>
      </div>
    </AdminLayout>
  );
}
