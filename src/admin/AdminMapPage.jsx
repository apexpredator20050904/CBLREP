import { useCallback, useEffect, useState } from "react";
import { apiFetch, pinForResource } from "./api";
import CommunityMap from "../components/CommunityMap";

const FILTERS = [
  ["all", "All Resources"],
  ["offers", "Offers"],
  ["needs", "Needs"],
  ["services", "Services"],
  ["flagged", "Flagged"],
];

const AdminMapPage = ({ showToast }) => {
  const [filter, setFilter] = useState("all");
  const [resources, setResources] = useState([]);
  const [selected, setSelected] = useState(null);

  const load = useCallback(async () => {
    try {
      const data = await apiFetch(`/api/admin/map?filter=${filter}`);
      setResources(data.resources || []);
    } catch (e) {
      showToast(e.message);
    }
  }, [filter, showToast]);

  useEffect(() => {
    load();
  }, [load]);

  const mappable = resources
    .map((r) => ({ ...r, coords: pinForResource(r) }))
    .filter((r) => r.coords);

  return (
    <section className="page-stack">
      <div className="filter-bar">
        {FILTERS.map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={`chip ${filter === id ? "chip--active" : ""}`}
            onClick={() => setFilter(id)}
          >
            {label}
          </button>
        ))}
        <span className="filter-count">{mappable.length} mapped pin(s)</span>
      </div>

      <CommunityMap
        resources={mappable.map((r) => ({
          ...r,
          title: r.name,
          lat: r.coords[0],
          lng: r.coords[1],
        }))}
        followLive={false}
        radiusMeters={6000}
      />

      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr><th>Resource</th><th>Category</th><th>Owner</th><th>Status</th><th>General location</th></tr>
          </thead>
          <tbody>
            {resources.length === 0 ? (
              <tr><td colSpan="5" className="table-empty">No resources for this filter.</td></tr>
            ) : (
              resources.map((r) => (
                <tr
                  key={r.id}
                  style={{ cursor: "pointer" }}
                  onClick={() => setSelected(r)}
                >
                  <td className="table-strong">{r.name}</td>
                  <td>{r.category}</td>
                  <td>{r.owner}</td>
                  <td>{r.status}</td>
                  <td>{r.location}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {selected ? (
        <div className="modal-backdrop" onClick={() => setSelected(null)}>
          <div className="modal-card" onClick={(e) => e.stopPropagation()}>
            <h3>{selected.name}</h3>
            <p><strong>Category:</strong> {selected.category}</p>
            <p><strong>Owner:</strong> {selected.owner}</p>
            <p><strong>Status:</strong> {selected.status}</p>
            <p><strong>General location:</strong> {selected.location}</p>
            <small>Only barangay-level location is shown — exact addresses and personal contact details are never exposed here.</small>
            <br /><br />
            <button type="button" className="close-btn" onClick={() => setSelected(null)}>Close</button>
          </div>
        </div>
      ) : null}
    </section>
  );
};

export default AdminMapPage;
