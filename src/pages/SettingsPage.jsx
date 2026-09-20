import { useEffect, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { COMMUNITY, TRINIDAD_BARANGAYS } from "../config/community";
import { clearAdminCache, downloadAdminBackup, fetchAdminSettings, saveAdminSettings } from "../services/adminApi";
import { btnGhost, btnPrimary } from "../components/ui";

const DEFAULT_MESSAGE = "The Trinidad portal is undergoing scheduled municipal updates. Please check back soon.";

function Toggle({ checked, onChange, label }) {
  return <button type="button" role="switch" aria-checked={checked} aria-label={label} onClick={() => onChange(!checked)} className={`relative h-6 w-11 rounded-full transition ${checked ? "bg-emerald-600" : "bg-stone-300"}`}><span className={`absolute top-1 h-4 w-4 rounded-full bg-white transition ${checked ? "left-6" : "left-1"}`} /></button>;
}

export default function SettingsPage() {
  const [draft, setDraft] = useState(null);
  const [newBarangay, setNewBarangay] = useState("");
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    fetchAdminSettings().then((response) => setDraft(response.settings)).catch((e) => setError(e.message));
  }, []);

  const update = (key, value) => setDraft((current) => ({ ...current, [key]: value }));
  const save = async () => {
    setBusy(true); setError(""); setNotice("");
    try {
      const response = await saveAdminSettings(draft);
      setDraft(response.settings);
      localStorage.setItem("cblrep_admin_theme", response.settings.theme);
      document.documentElement.classList.toggle("dark", response.settings.theme === "dark");
      setNotice("System settings saved.");
    } catch (e) { setError(e.message); } finally { setBusy(false); }
  };
  const addBarangay = () => {
    const value = newBarangay.trim();
    if (value && !draft.activeBarangays.includes(value)) update("activeBarangays", [...draft.activeBarangays, value]);
    setNewBarangay("");
  };
  const removeBarangay = (value) => update("activeBarangays", draft.activeBarangays.filter((item) => item !== value));
  const runCacheClear = async () => { setBusy(true); try { await clearAdminCache(); setNotice("Application cache cleared."); } catch (e) { setError(e.message); } finally { setBusy(false); } };
  const runBackup = async () => { setBusy(true); setError(""); try { await downloadAdminBackup(); setNotice("Database backup downloaded."); } catch (e) { setError(e.message); } finally { setBusy(false); } };

  return <AdminLayout title="Settings">
    {error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>}
    {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{notice}</p>}
    {!draft ? <p className="text-sm text-stone-500">Loading system settings…</p> : <div className="space-y-5">
      <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h2 className="text-lg font-extrabold text-emerald-950">System appearance</h2><p className="mt-1 text-sm text-stone-500">Choose the admin console theme. This does not change member-facing content.</p><div className="mt-4 flex items-center justify-between border-t border-stone-100 pt-4"><div><p className="font-semibold text-stone-800">Dark mode</p><p className="text-sm text-stone-500">Use a dark interface for this dashboard.</p></div><Toggle checked={draft.theme === "dark"} label="Dark mode" onChange={(value) => update("theme", value ? "dark" : "light")} /></div></div>
      <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h2 className="text-lg font-extrabold text-emerald-950">Platform maintenance</h2><p className="mt-1 text-sm text-stone-500">When enabled, the Flutter app can show the municipal maintenance notice.</p><div className="mt-4 flex items-center justify-between border-t border-stone-100 pt-4"><div><p className="font-semibold text-stone-800">Maintenance mode</p><p className="text-sm text-stone-500">{draft.maintenanceMode ? "Portal notice is active." : "Portal is operating normally."}</p></div><Toggle checked={draft.maintenanceMode} label="Platform maintenance mode" onChange={(value) => update("maintenanceMode", value)} /></div>{draft.maintenanceMode && <label className="mt-4 block text-sm font-semibold text-stone-700">Maintenance message<textarea rows="3" value={draft.maintenanceMessage || DEFAULT_MESSAGE} onChange={(e) => update("maintenanceMessage", e.target.value)} className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label>}</div>
      <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h2 className="text-lg font-extrabold text-emerald-950">Municipal scope</h2><p className="mt-1 text-sm text-stone-500">Locked location scope: <strong>{COMMUNITY.label}</strong>. Manage active barangay options below.</p><div className="mt-4 flex flex-wrap gap-2">{draft.activeBarangays.map((barangay) => <span key={barangay} className="inline-flex items-center gap-2 rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-900">{barangay}<button type="button" aria-label={`Remove ${barangay}`} onClick={() => removeBarangay(barangay)}>×</button></span>)}</div><div className="mt-4 flex gap-2"><select value={newBarangay} onChange={(e) => setNewBarangay(e.target.value)} className="flex-1 rounded-lg border border-stone-300 px-3 py-2 text-sm"><option value="">Select a Trinidad barangay</option>{TRINIDAD_BARANGAYS.filter((item) => !draft.activeBarangays.includes(item)).map((item) => <option key={item}>{item}</option>)}</select><button type="button" className={btnGhost} onClick={addBarangay}>Add</button></div></div>
      <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h2 className="text-lg font-extrabold text-emerald-950">Data maintenance</h2><p className="mt-1 text-sm text-stone-500">Administrative operations only. Backup downloads use the configured MySQL database.</p><div className="mt-4 flex flex-wrap gap-2"><button type="button" disabled={busy} className={btnGhost} onClick={runCacheClear}>Clear system cache</button><button type="button" disabled={busy} className={btnPrimary} onClick={runBackup}>Download database backup</button></div></div>
      <div className="flex justify-end"><button disabled={busy} className={btnPrimary} onClick={save}>{busy ? "Saving…" : "Save system settings"}</button></div>
    </div>}
  </AdminLayout>;
}
