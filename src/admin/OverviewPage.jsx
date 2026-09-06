import { useEffect, useState } from "react";
import { apiFetch } from "./api";

const CARDS = [
  ["totalUsers", "Total Users", "👥"],
  ["verifiedUsersCount", "Verified Users", "✅"],
  ["pendingVerificationCount", "Pending Verifications", "⏳"],
  ["activeListings", "Active Resources", "📦"],
  ["openFlaggedContent", "Flagged Resources", "🚩"],
  ["totalExchanges", "Total Exchanges", "🔄"],
  ["completedExchanges", "Completed Exchanges", "🤝"],
  ["totalTimeBankTransactions", "Time-Bank Transactions", "⏱️"],
  ["pendingReports", "Pending Reports", "📋"],
];

const OverviewPage = ({ onNavigate }) => {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    apiFetch("/api/admin/dashboard")
      .then(setData)
      .catch((e) => setError(e.message));
  }, []);

  if (error)
    return (
      <section className="page-stack">
        <div className="table-card">
          <p className="table-empty">Failed to load dashboard: {error}</p>
        </div>
      </section>
    );
  if (!data) return <section className="page-stack"><p>Loading live database statistics…</p></section>;

  return (
    <section className="page-stack">
      <div className="dashboard-stats-grid">
        {CARDS.map(([key, label, icon]) => (
          <div className="stat-card" key={key}>
            <span>{icon}</span>
            <p className="stat-label">{label}</p>
            <h3 className="stat-value">{data[key] ?? 0}</h3>
          </div>
        ))}
      </div>

      <div className="dashboard-columns">
        <div className="dashboard-column-main">
          <div className="dashboard-section-header">
            <h3 className="dashboard-section-title">Recent System Activity</h3>
            <button type="button" onClick={() => onNavigate("logs")} className="link-btn">
              View audit logs →
            </button>
          </div>
          <div className="dashboard-activity-card">
            {(data.recentActions || []).length === 0 ? (
              <p className="table-empty">No recent activity recorded yet.</p>
            ) : (
              data.recentActions.map((a, i) => (
                <div className="activity-row" key={i}>
                  <div>
                    <strong>{a.title}</strong>
                    <p>{a.description}</p>
                  </div>
                  <small>{a.time}</small>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="dashboard-column-side">
          <div className="dashboard-section-header">
            <h3 className="dashboard-section-title">Community Health</h3>
          </div>
          <div className="dashboard-activity-card">
            <div className="health-row">
              <span>Verification rate</span>
              <strong>{data.verifiedUsersPercent}</strong>
            </div>
            <div className="health-row">
              <span>Pending verification</span>
              <strong>{data.pendingVerificationPercent}</strong>
            </div>
            <div className="health-row">
              <span>Listings awaiting review</span>
              <strong>{data.pendingReviewListings ?? 0}</strong>
            </div>
            <div className="health-row">
              <span>Exchanges this month</span>
              <strong>{data.exchangesThisMonth ?? 0}</strong>
            </div>
            <div className="health-row">
              <span>Time-Bank hours delivered</span>
              <strong>{data.timeBankHoursTotal}</strong>
            </div>
            <div className="health-row">
              <span>Awaiting confirmation</span>
              <strong>{data.pendingTimeBankConfirmations ?? 0}</strong>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default OverviewPage;
