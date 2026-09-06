import { useEffect, useState } from "react";
import { apiFetch } from "./api";

const SettingsPage = ({ showToast }) => {
  const [settings, setSettings] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    apiFetch("/api/admin/settings")
      .then((d) => setSettings(d.settings || {}))
      .catch((e) => showToast(e.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toggle = (key) => async () => {
    const next = { ...settings, [key]: !settings[key] };
    setSettings(next);
    setSaving(true);
    try {
      await apiFetch("/api/admin/settings", {
        method: "POST",
        body: JSON.stringify({ [key]: next[key] }),
      });
      showToast("Setting saved");
    } catch (e) {
      showToast(e.message);
      setSettings(settings); // revert on failure
    } finally {
      setSaving(false);
    }
  };

  if (!settings) return <section className="page-stack"><p>Loading settings…</p></section>;

  const flags = [
    ["autoApproveListings", "Auto-approve new resource listings", "When off, admins review each listing before it goes live."],
    ["requireProfileVerification", "Require profile verification", "Members must be verified before joining exchanges."],
    ["maintenanceMode", "Maintenance mode", "Temporarily lock member access to the portal."],
  ];

  return (
    <section className="page-stack">
      <div className="page-heading">
        <div>
          <h2 className="page-title">Administrative Settings</h2>
          <p className="page-subtitle">System-wide configuration managed by administrators</p>
        </div>
        {settings.updated_by ? (
          <span className="type-badge badge-default">
            Last updated by {settings.updated_by}
          </span>
        ) : null}
      </div>

      <div className="table-card">
        {flags.map(([key, label, hint]) => (
          <div className="health-row" key={key}>
            <span>
              <strong>{label}</strong>
              <br />
              <small>{hint}</small>
            </span>
            <button
              type="button"
              className={`chip ${settings[key] ? "chip--on" : ""}`}
              disabled={saving}
              onClick={toggle(key)}
            >
              {settings[key] ? "Enabled" : "Disabled"}
            </button>
          </div>
        ))}
      </div>
    </section>
  );
};

export default SettingsPage;
