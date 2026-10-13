import { useCallback, useEffect, useRef, useState } from "react";
import AdminLayout from "../components/AdminLayout";
import { clearAdminCache, downloadAdminBackup, fetchAdminSettings, saveAdminSettings } from "../services/adminApi";
import { btnGhost, btnPrimary } from "../components/ui";
import TwoFactorSetup from "../components/AdminTwoFactorSetup";

const DEFAULT_MESSAGE = "The Trinidad portal is undergoing scheduled municipal updates. Please check back soon.";
const DEBOUNCE_MS = 600;
const TOAST_DURATION = 2500;

const SETTING_LABELS = {
  theme: "Theme",
  maintenanceMode: "Maintenance mode",
  maintenanceMessage: "Maintenance message",
};

// ── Toast ──────────────────────────────────────────────────
function Toast({ toast }) {
  if (!toast) return null;
  const isError = toast.type === "error";
  return (
    <div
      role={isError ? "alert" : "status"}
      className={`fixed bottom-6 right-6 z-50 flex items-center gap-2 rounded-xl border px-4 py-3 text-sm font-medium shadow-lg transition-all duration-300 ${
        isError
          ? "border-red-200 bg-red-50 text-red-700"
          : "border-emerald-200 bg-emerald-50 text-emerald-900"
      }`}
    >
      <span className={`inline-block h-2 w-2 rounded-full ${isError ? "bg-red-500" : "bg-emerald-500"}`} />
      {toast.message}
    </div>
  );
}

// ── Toggle with saving indicator ───────────────────────────
function Toggle({ checked, onChange, label, saving }) {
  return (
    <div className="flex items-center gap-2">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={saving}
        onClick={() => onChange(!checked)}
        className={`relative h-6 w-11 rounded-full transition disabled:opacity-60 ${
          checked ? "bg-emerald-600" : "bg-stone-300"
        }`}
      >
        <span
          className={`absolute top-1 h-4 w-4 rounded-full bg-white transition ${
            checked ? "left-6" : "left-1"
          }`}
        />
      </button>
      {saving && (
        <span className="h-3 w-3 animate-spin rounded-full border-2 border-emerald-600 border-t-transparent" />
      )}
    </div>
  );
}

// ── Main component ─────────────────────────────────────────
export default function SettingsPage() {
  const [draft, setDraft] = useState(null);
  const [toast, setToast] = useState(null);
  const [saving, setSaving] = useState({});
  const [busy, setBusy] = useState(false);
  const debounceRef = useRef(null);
  const toastTimer = useRef(null);

  // ── Toast helper ──────────────────────────────────────
  const showToast = useCallback((message, type = "success") => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast({ message, type });
    toastTimer.current = setTimeout(() => setToast(null), TOAST_DURATION);
  }, []);

  // ── Fetch settings on mount ───────────────────────────
  useEffect(() => {
    fetchAdminSettings()
      .then((response) => {
        setDraft(response.settings);
        localStorage.setItem("cblrep_admin_theme", response.settings.theme);
        document.documentElement.classList.toggle("dark", response.settings.theme === "dark");
      })
      .catch((e) => showToast(e.message, "error"));
  }, [showToast]);

  // ── Cleanup timers on unmount ─────────────────────────
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      if (toastTimer.current) clearTimeout(toastTimer.current);
    };
  }, []);

  // ── Persist a single setting ──────────────────────────
  const persistSetting = useCallback(async (key, value) => {
    setSaving((s) => ({ ...s, [key]: true }));
    try {
      const response = await saveAdminSettings({ [key]: value });
      setDraft(response.settings);
      if (key === "theme") {
        localStorage.setItem("cblrep_admin_theme", response.settings.theme);
        document.documentElement.classList.toggle("dark", response.settings.theme === "dark");
      }
      showToast(`${SETTING_LABELS[key] || key} updated.`, "success");
    } catch (e) {
      showToast(e.message, "error");
    } finally {
      setSaving((s) => ({ ...s, [key]: false }));
    }
  }, [showToast]);

  // ── Debounced persist for text inputs ─────────────────
  const debouncedPersist = useCallback((key, value) => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => persistSetting(key, value), DEBOUNCE_MS);
  }, [persistSetting]);

  // ── Data maintenance operations ───────────────────────
  const runCacheClear = async () => {
    setBusy(true);
    try {
      await clearAdminCache();
      showToast("Application cache cleared.", "success");
    } catch (e) {
      showToast(e.message, "error");
    } finally {
      setBusy(false);
    }
  };

  const runBackup = async () => {
    setBusy(true);
    try {
      await downloadAdminBackup();
      showToast("Database backup downloaded.", "success");
    } catch (e) {
      showToast(e.message, "error");
    } finally {
      setBusy(false);
    }
  };

  // ── Render ────────────────────────────────────────────
  return (
    <AdminLayout title="Settings">
      <Toast toast={toast} />
      {!draft ? (
        <p className="text-sm text-stone-500">Loading system settings…</p>
      ) : (
        <div className="space-y-5">
          {/* Account security */}
          <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            <h2 className="text-lg font-extrabold text-emerald-950">Account security</h2>
            <p className="mt-1 text-sm text-stone-500">
              Applies to the administrator account you are signed in with, not to the portal as a whole.
            </p>
            <div className="mt-4 border-t border-stone-100 pt-4">
              <TwoFactorSetup />
            </div>
          </div>

          {/* System appearance */}
          <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            <h2 className="text-lg font-extrabold text-emerald-950">System appearance</h2>
            <p className="mt-1 text-sm text-stone-500">
              Choose the admin console theme. This does not change member-facing content.
            </p>
            <div className="mt-4 flex items-center justify-between border-t border-stone-100 pt-4">
              <div>
                <p className="font-semibold text-stone-800">Dark mode</p>
                <p className="text-sm text-stone-500">Use a dark interface for this dashboard.</p>
              </div>
              <Toggle
                checked={draft.theme === "dark"}
                label="Dark mode"
                saving={saving.theme}
                onChange={(value) => {
                  const newTheme = value ? "dark" : "light";
                  setDraft((current) => ({ ...current, theme: newTheme }));
                  persistSetting("theme", newTheme);
                }}
              />
            </div>
          </div>

          {/* Platform maintenance */}
          <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            <h2 className="text-lg font-extrabold text-emerald-950">Platform maintenance</h2>
            <p className="mt-1 text-sm text-stone-500">
              When enabled, the Flutter app can show the municipal maintenance notice.
            </p>
            <div className="mt-4 flex items-center justify-between border-t border-stone-100 pt-4">
              <div>
                <p className="font-semibold text-stone-800">Maintenance mode</p>
                <p className="text-sm text-stone-500">
                  {draft.maintenanceMode ? "Portal notice is active." : "Portal is operating normally."}
                </p>
              </div>
              <Toggle
                checked={draft.maintenanceMode}
                label="Platform maintenance mode"
                saving={saving.maintenanceMode}
                onChange={(value) => {
                  setDraft((current) => ({ ...current, maintenanceMode: value }));
                  persistSetting("maintenanceMode", value);
                }}
              />
            </div>
            {draft.maintenanceMode && (
              <label className="mt-4 block text-sm font-semibold text-stone-700">
                Maintenance message
                <textarea
                  rows="3"
                  value={draft.maintenanceMessage || DEFAULT_MESSAGE}
                  onChange={(e) => {
                    const value = e.target.value;
                    setDraft((current) => ({ ...current, maintenanceMessage: value }));
                    debouncedPersist("maintenanceMessage", value);
                  }}
                  className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2"
                />
                {saving.maintenanceMessage && (
                  <span className="mt-1 block text-xs text-emerald-600">Saving…</span>
                )}
              </label>
            )}
          </div>

          {/* Data maintenance */}
          <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            <h2 className="text-lg font-extrabold text-emerald-950">Data maintenance</h2>
            <p className="mt-1 text-sm text-stone-500">
              Administrative operations only. Backup downloads use the configured MySQL database.
            </p>
            <div className="mt-4 flex flex-wrap gap-2">
              <button type="button" disabled={busy} className={btnGhost} onClick={runCacheClear}>
                Clear system cache
              </button>
              <button type="button" disabled={busy} className={btnPrimary} onClick={runBackup}>
                Download database backup
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminLayout>
  );
}
