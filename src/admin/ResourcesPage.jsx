import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";

const ResourcesPage = ({ kind = "all", showToast }) => {
  const [resources, setResources] = useState([]);
  const [category, setCategory] = useState("all");

  const load = useCallback(async () => {
    try {
      const data = await apiFetch(`/api/admin/resources?kind=${kind}`);
      setResources(data.resources || []);
    } catch (e) {
      showToast(e.message);
    }
  }, [kind, showToast]);

  useEffect(() => {
    load();
  }, [load]);

  const moderate = async (r, action) => {
    let reason = "";
    if (["remove", "hide"].includes(action)) {
      reason = window.prompt(`Reason for ${action}ing "${r.title}"? (required)`);
      if (!reason || !reason.trim()) return showToast("A reason is required for moderation actions.");
    }
    try {
      await apiFetch(`/api/admin/resources/${r.id}/moderate`, {
        method: "POST",
        body: JSON.stringify({ action, reason }),
      });
      showToast(`Listing ${action}d`);
      load();
    } catch (e) {
      showToast(e.message);
    }
  };

  const cats = ["all", ...new Set(resources.map((r) => r.category).filter(Boolean))];
  const visible = category === "all" ? resources : resources.filter((r) => r.category === category);

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <select className="filter-select" value={category} onChange={(e) => setCategory(e.target.value)}>
          {cats.map((c) => (
            <option key={c} value={c}>{c === "all" ? "All categories" : c}</option>
          ))}
        </select>
        <span className="filter-count">{visible.length} listing(s)</span>
      </div>

      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr>
              <th>Listing</th><th>Type</th><th>Category</th><th>Owner</th>
              <th>Status</th><th>Location</th><th>Moderation</th>
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr><td colSpan="7" className="table-empty">No listings in this view.</td></tr>
            ) : (
              visible.map((r) => (
                <tr key={r.id}>
                  <td className="table-strong">{r.title}</td>
                  <td><span className="type-badge badge-default">{r.type || "—"}</span></td>
                  <td>{r.category}</td>
                  <td>{r.user?.name}</td>
                  <td>
                    <span
                      className={`type-badge ${
                        r.admin_status === "Removed"
                          ? "badge-danger"
                          : r.admin_status === "Flagged"
                            ? "badge-warn"
                            : "badge-success"
                      }`}
                    >
                      {r.admin_status}
                    </span>
                  </td>
                  <td>{r.location}</td>
                  <td className="table-actions">
                    <button type="button" onClick={() => moderate(r, "approve")}>Approve</button>
                    <button type="button" onClick={() => moderate(r, "flag")}>Flag</button>
                    <button type="button" className="warn" onClick={() => moderate(r, "hide")}>Hide</button>
                    <button type="button" className="danger" onClick={() => moderate(r, "remove")}>Remove</button>
                    {r.status === "removed" || r.status === "hidden" ? (
                      <button type="button" onClick={() => moderate(r, "restore")}>Restore</button>
                    ) : null}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
};

export default ResourcesPage;
