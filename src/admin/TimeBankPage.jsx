import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";

const TimeBankPage = ({ showToast }) => {
  const [data, setData] = useState(null);

  const load = useCallback(async () => {
    try {
      setData(await apiFetch("/api/admin/timebank"));
    } catch (e) {
      showToast(e.message);
    }
  }, [showToast]);

  useEffect(() => {
    load();
  }, [load]);

  if (!data) return <section className="page-stack"><p>Loading Time-Bank records…</p></section>;

  return (
    <section className="page-stack">
      <div className="timebank-callout">
        <strong>⏱ Time-Bank rule</strong>
        <b>1 verified hour of service = 1 Time Credit.</b> Credits are generated
        only through confirmed service transactions — balances cannot be edited
        manually by anyone, including administrators.
      </div>

      <div className="dashboard-stats-grid">
        <div className="stat-card stat--accent">
          <p className="stat-label">Total Credits Earned</p>
          <h3 className="stat-value dashboard-stat-number stat-positive">{data.totals.creditsEarned}</h3>
        </div>
        <div className="stat-card stat--accent">
          <p className="stat-label">Total Credits Spent</p>
          <h3 className="stat-value dashboard-stat-number">{data.totals.creditsSpent}</h3>
        </div>
        <div className="stat-card">
          <p className="stat-label">Active Transactions</p>
          <h3 className="stat-value">{data.totals.active}</h3>
        </div>
        <div className="stat-card">
          <p className="stat-label">Pending Confirmations</p>
          <h3 className="stat-value dashboard-stat-number stat-amber">{data.totals.pendingConfirmations}</h3>
        </div>
        <div className="stat-card">
          <p className="stat-label">Completed Transactions</p>
          <h3 className="stat-value">{data.totals.completed}</h3>
        </div>
        <div className="stat-card">
          <p className="stat-label">Disputed</p>
          <h3 className="stat-value dashboard-stat-number stat-negative">{data.totals.disputed}</h3>
        </div>
      </div>

      <div className="table-card">
        <h3 className="table-card-title">Time-Bank transactions (inspect only)</h3>
        <table className="data-table">
          <thead>
            <tr>
              <th>TX</th><th>Service</th><th>Provider</th><th>Requester</th>
              <th>Hours</th><th>Credits</th><th>Status</th><th>Confirmed</th><th>Date</th>
            </tr>
          </thead>
          <tbody>
            {data.transactions.length === 0 ? (
              <tr><td colSpan="9" className="table-empty">No Time-Bank transactions yet.</td></tr>
            ) : (
              data.transactions.map((t) => (
                <tr key={String(t.transaction_id)}>
                  <td>{t.transaction_id}</td>
                  <td className="table-strong">{t.service}</td>
                  <td>{t.provider}</td>
                  <td>{t.requester}</td>
                  <td>{t.hours_completed ?? t.hours_requested}</td>
                  <td>{t.credits ?? "—"}</td>
                  <td>
                    <span className={`type-badge ${t.status === "Completed" ? "badge-success" : t.disputed ? "badge-danger" : "badge-warn"}`}>
                      {t.status}
                    </span>
                  </td>
                  <td>{t.confirmation_status || "—"}</td>
                  <td>{t.created}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="table-card">
        <h3 className="table-card-title">Member balances (read-only ledger view)</h3>
        <table className="data-table">
          <thead><tr><th>Member</th><th>Email</th><th>Time Credit Balance</th></tr></thead>
          <tbody>
            {data.balances.map((b) => (
              <tr key={b.email}>
                <td className="table-strong">{b.name}</td>
                <td>{b.email}</td>
                <td>{b.time_credit_balance} credits ⏰</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
};

export default TimeBankPage;
