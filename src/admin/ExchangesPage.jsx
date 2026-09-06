import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "./api";

const TYPE_MAP = {
  all: "all",
  freecycling: "freecycling",
  bartering: "bartering",
  lending: "lending",
  timebank: "timebank",
};

const ExchangesPage = ({ type = "all", showToast }) => {
  const [exchanges, setExchanges] = useState([]);
  const [status, setStatus] = useState("all");

  const load = useCallback(async () => {
    try {
      const t = TYPE_MAP[type] ?? "all";
      const data = await apiFetch(
        `/api/admin/exchanges?type=${t}&status=${encodeURIComponent(status)}`,
      );
      setExchanges(data.exchanges || []);
    } catch (e) {
      showToast(e.message);
    }
  }, [type, status, showToast]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <section className="page-stack">
      <div className="filter-bar">
        <select className="filter-select" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="all">All statuses</option>
          <option value="pending">Pending</option>
          <option value="active">Active / In Progress</option>
          <option value="completed">Completed</option>
          <option value="cancel">Cancelled</option>
        </select>
        <span className="filter-count">{exchanges.length} exchange(s)</span>
      </div>

      <div className="table-card">
        <table className="data-table">
          <thead>
            <tr>
              <th>Transaction ID</th><th>Exchange Type</th><th>Users</th>
              <th>Resource / Service</th><th>Status</th><th>Date</th>
            </tr>
          </thead>
          <tbody>
            {exchanges.length === 0 ? (
              <tr><td colSpan="6" className="table-empty">No exchanges recorded for this filter.</td></tr>
            ) : (
              exchanges.map((e) => (
                <tr key={String(e.transaction_id)}>
                  <td>{e.transaction_id}</td>
                  <td><span className="type-badge badge-default">{e.exchange_type}</span></td>
                  <td>{e.users}</td>
                  <td className="table-strong">
                    {e.resource}
                    {e.disputed ? " 🚩" : ""}
                  </td>
                  <td>{e.status}</td>
                  <td>{e.date}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
};

export default ExchangesPage;
