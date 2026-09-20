import { useCallback, useEffect, useState } from "react";
import { apiFetch, downloadCSV, openPDF } from "./api";

const AnalyticsPage = ({ showToast }) => {
  const [data, setData] = useState(null);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const load = useCallback(async () => {
    const params = new URLSearchParams();
    if (from) params.set("from", from);
    if (to) params.set("to", to);
    try {
      setData(await apiFetch(`/api/admin/analytics?${params.toString()}`));
    } catch (e) {
      showToast(e.message);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [from, to]);

  useEffect(() => {
    load();
  }, [load]);

  if (!data) return <section className="page-stack"><p>Computing analytics from the database…</p></section>;

  const csvParams = { from: from || undefined, to: to || undefined };

  const verifiedByBarangay = data.users?.verifiedByBarangay || [];

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <label>From <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label>To <input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        <button type="button" className="chip" onClick={() => downloadCSV(csvParams)}>⬇ Export CSV</button>
        <button type="button" className="chip" onClick={() => openPDF(csvParams)}>🖨 Export PDF</button>
      </div>

      <div className="dashboard-columns">
        <div className="dashboard-column-main">
          <h3 className="dashboard-section-title">User Statistics</h3>
          <div className="dashboard-activity-card">
            <div className="health-row"><span>Total users</span><strong>{data.users.total}</strong></div>
            <div className="health-row"><span>Verified users</span><strong>{data.users.verified}</strong></div>
            <div className="health-row"><span>Pending users</span><strong>{data.users.pending}</strong></div>
            <div className="health-row"><span>Suspended users</span><strong>{data.users.suspended}</strong></div>
          </div>

          <h3 className="dashboard-section-title">Resource Statistics</h3>
          <div className="dashboard-activity-card">
            <div className="health-row"><span>Total resources</span><strong>{data.resources.total}</strong></div>
            <div className="health-row"><span>Offers</span><strong>{data.resources.offers}</strong></div>
            <div className="health-row"><span>Needs</span><strong>{data.resources.needs}</strong></div>
            <div className="health-row"><span>Active</span><strong>{data.resources.active}</strong></div>
            <div className="health-row"><span>Removed</span><strong>{data.resources.removed}</strong></div>
          </div>

          <h3 className="dashboard-section-title">Exchange Statistics</h3>
          <div className="dashboard-activity-card">
            <div className="health-row"><span>Freecycling</span><strong>{data.exchanges.freecycling}</strong></div>
            <div className="health-row"><span>Bartering</span><strong>{data.exchanges.bartering}</strong></div>
            <div className="health-row"><span>Lending</span><strong>{data.exchanges.lending}</strong></div>
            <div className="health-row"><span>Time Banking</span><strong>{data.exchanges.timeBanking}</strong></div>
            <div className="health-row"><span>Completed exchanges</span><strong>{data.exchanges.completed}</strong></div>
            <div className="health-row"><span>Cancelled exchanges</span><strong>{data.exchanges.cancelled}</strong></div>
            <div className="health-row"><span>Disputed exchanges</span><strong>{data.exchanges.disputed}</strong></div>
          </div>
        </div>

        <div className="dashboard-column-side">
          <h3 className="dashboard-section-title">Resources by Barangay</h3>
          <div className="dashboard-activity-card">
            {data.exchanges.byBarangay.map((b) => (
              <div className="health-row" key={b.location}>
                <span>{b.location || "Unspecified"}</span>
                <strong>{b.count}</strong>
              </div>
            ))}
          </div>

          <h3 className="dashboard-section-title">Verified Residents by Barangay</h3>
          <div className="dashboard-activity-card">
            {verifiedByBarangay.length === 0 ? (
              <p className="table-empty">No verified residents found.</p>
            ) : (
              verifiedByBarangay.map((b) => (
                <div className="health-row" key={b.barangay}>
                  <span>{b.barangay}</span>
                  <strong>{b.verified} resident{b.verified !== 1 ? "s" : ""}{b.students ? " ("+b.students+" student"+(b.students !== 1 ? "s" : "")+") " : ""}</strong>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </section>
  );
};

export default AnalyticsPage;
