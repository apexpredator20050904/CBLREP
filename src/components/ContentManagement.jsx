import { useEffect, useState } from "react";
import { createContentPage, deleteContentPage, fetchContentPages, updateContentPage } from "../services/adminApi";
import { EmptyRow, StatCard, StatusBadge, btnGhost, btnPrimary, tdClass, tdStrongClass, theadClass } from "./ui";

const EMPTY = { title: "", slug: "", body: "", status: "draft" };

export default function ContentManagement() {
  const [data, setData] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const load = () => fetchContentPages().then(setData).catch((e) => setError(e.message));
  useEffect(() => { load(); }, []);
  const submit = async (event) => {
    event.preventDefault(); setBusy(true); setError("");
    try { await createContentPage(form); setForm(EMPTY); setOpen(false); await load(); }
    catch (e) { setError(e.message); } finally { setBusy(false); }
  };
  const toggle = async (page) => {
    try { await updateContentPage(page.id, { status: page.status === "published" ? "draft" : "published" }); await load(); }
    catch (e) { setError(e.message); }
  };
  const remove = async (page) => {
    if (!window.confirm(`Delete "${page.title}"?`)) return;
    try { await deleteContentPage(page.id); await load(); } catch (e) { setError(e.message); }
  };
  return <section className="space-y-5">
    {error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>}
    <div className="grid gap-4 sm:grid-cols-3">
      <StatCard icon="📄" label="Total pages" value={data?.summary?.total} />
      <StatCard icon="✅" label="Published" value={data?.summary?.published} accent />
      <StatCard icon="📝" label="Drafts" value={data?.summary?.drafts} />
    </div>
    <div className="flex items-center justify-between gap-3"><div><h2 className="text-lg font-extrabold text-emerald-950">Content pages</h2><p className="text-sm text-stone-500">Manage public information for Trinidad residents.</p></div><button className={btnPrimary} onClick={() => setOpen(true)}>+ New Page</button></div>
    <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="overflow-x-auto"><table className="min-w-full text-left text-sm"><thead className={theadClass}><tr><th className="px-4 py-3">Page</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Updated</th><th className="px-4 py-3 text-right">Actions</th></tr></thead><tbody className="divide-y divide-stone-100">
      {!data ? <EmptyRow colSpan={4}>Loading content pages…</EmptyRow> : data.pages?.length === 0 ? <EmptyRow colSpan={4}>No content pages yet. Create the first Trinidad guide.</EmptyRow> : data.pages.map((page) => <tr key={page.id}><td className={tdStrongClass}><div>{page.title}</div><div className="text-xs font-normal text-stone-400">/{page.slug}</div></td><td className={tdClass}><StatusBadge tone={page.status === "published" ? "success" : "warn"}>{page.status}</StatusBadge></td><td className={tdClass}>{page.updated_at || "—"}</td><td className={`${tdClass} text-right`}><button className={btnGhost} onClick={() => toggle(page)}>{page.status === "published" ? "Unpublish" : "Publish"}</button>{" "}<button className="text-xs font-semibold text-red-700 hover:underline" onClick={() => remove(page)}>Delete</button></td></tr>)}
    </tbody></table></div></div>
    {open && <div className="fixed inset-0 z-20 grid place-items-center bg-emerald-950/40 p-4"><form onSubmit={submit} className="w-full max-w-lg space-y-4 rounded-2xl bg-white p-6 shadow-xl"><div className="flex items-center justify-between"><h2 className="text-lg font-extrabold text-emerald-950">Create content page</h2><button type="button" onClick={() => setOpen(false)}>✕</button></div><label className="block text-sm font-semibold">Title<input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label><label className="block text-sm font-semibold">URL slug <span className="font-normal text-stone-400">(optional)</span><input value={form.slug} onChange={(e) => setForm({ ...form, slug: e.target.value })} placeholder="waste-segregation-guide" className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label><label className="block text-sm font-semibold">Body<textarea rows="5" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label><label className="block text-sm font-semibold">Save as<select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })} className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2"><option value="draft">Draft</option><option value="published">Published</option></select></label><div className="flex justify-end gap-2"><button type="button" className={btnGhost} onClick={() => setOpen(false)}>Cancel</button><button disabled={busy} className={btnPrimary}>{busy ? "Saving…" : "Save page"}</button></div></form></div>}
  </section>;
}
