import React, { useState } from "react";
import logo from "../assets/logo.jpg";
import { COMMUNITY } from "../config/community";

const ADMIN_NAV = [
  { id: "overview", label: "Dashboard", icon: "🛡️" },
  {
    group: "Users",
    icon: "👥",
    items: [
      { id: "users", label: "All Users", icon: "•" },
      { id: "verification", label: "Verification", icon: "•" },
      { id: "suspended", label: "Suspended Users", icon: "•" },
    ],
  },
  {
    group: "Resources",
    icon: "📦",
    items: [
      { id: "admin_listings", label: "All Listings", icon: "•" },
      { id: "listings_offers", label: "Offers", icon: "•" },
      { id: "listings_needs", label: "Needs", icon: "•" },
      { id: "listings_flagged", label: "Flagged", icon: "•" },
    ],
  },
  {
    group: "Exchanges",
    icon: "🔄",
    items: [
      { id: "admin_exchanges", label: "All Exchanges", icon: "•" },
      { id: "ex_freecycle", label: "Freecycling", icon: "•" },
      { id: "ex_barter", label: "Bartering", icon: "•" },
      { id: "ex_lend", label: "Lending", icon: "•" },
      { id: "ex_timebank", label: "Time Banking", icon: "•" },
    ],
  },
  { id: "reports", label: "Reports & Moderation", icon: "🚩" },
  { id: "map", label: "Community Map", icon: "🗺️" },
  { id: "analytics", label: "Analytics & Reports", icon: "📈" },
  { id: "logs", label: "Audit Logs", icon: "📋" },
  { id: "settings", label: "Settings", icon: "⚙️" },
];

const PAGE_TITLES = {
  overview: "Admin Dashboard",
  users: "User Management",
  verification: "Verification Management",
  suspended: "Suspended Users",
  admin_listings: "Resource Management",
  listings_offers: "Offers",
  listings_needs: "Needs",
  listings_flagged: "Flagged Resources",
  admin_exchanges: "Exchange Management",
  ex_freecycle: "Freecycling Exchanges",
  ex_barter: "Bartering Exchanges",
  ex_lend: "Lending Exchanges",
  ex_timebank: "Time-Bank Transactions",
  reports: "Reports & Moderation",
  map: "Community Map",
  analytics: "Analytics & Reports",
  logs: "Audit Logs",
  settings: "Administrative Settings",
};

// Admin-only shell for the System Administrator console. The member variant
// was removed along with the member web portal (the mobile app replaces it).
const PortalLayout = ({
  userName,
  barangayName,
  initials,
  activeTab,
  onNavigate,
  onLogout,
  notifications = [],
  children,
}) => {
  const [showNotes, setShowNotes] = useState(false);
  const title = PAGE_TITLES[activeTab] || "Admin Panel";

  return (
    <div className="dashboard-shell dashboard-shell--admin">
      <aside className="dashboard-sidebar">
        <div>
          <div className="dashboard-sidebar-header">
            <div className="dashboard-sidebar-logo-wrap">
              <img src={logo} alt="" className="dashboard-logo" />
            </div>
            <div className="dashboard-brand-text">
              <span className="dashboard-brand-title">CBLREP ADMIN</span>
              <span className="dashboard-brand-subtitle">
                {COMMUNITY.shortLabel}
              </span>
            </div>
          </div>

          <div className="dashboard-user-card">
            <div className="dashboard-user-avatar">{initials}</div>
            <div>
              <div className="dashboard-user-name">{userName}</div>
              <div className="dashboard-user-location">{barangayName}</div>
            </div>
            <span className="dashboard-verified-badge">✓</span>
          </div>

          <nav className="dashboard-nav-menu" aria-label="Admin">
            {ADMIN_NAV.map((item) =>
              item.group ? (
                <React.Fragment key={item.group}>
                  <div className="dashboard-nav-group">
                    <span>{item.icon}</span>
                    {item.group}
                  </div>
                  {item.items.map((sub) => (
                    <button
                      key={sub.id}
                      type="button"
                      onClick={() => onNavigate(sub.id)}
                      className={`dashboard-nav-item dashboard-nav-item--sub ${
                        activeTab === sub.id ? "dashboard-nav-item--active" : ""
                      }`}
                    >
                      <span>{sub.icon}</span>
                      <span>{sub.label}</span>
                    </button>
                  ))}
                </React.Fragment>
              ) : (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => onNavigate(item.id)}
                  className={`dashboard-nav-item ${
                    activeTab === item.id ? "dashboard-nav-item--active" : ""
                  }`}
                >
                  <span>{item.icon}</span>
                  <span>{item.label}</span>
                </button>
              ),
            )}
          </nav>
        </div>
        <div className="dashboard-sidebar-footer">
          <div className="dashboard-time-balance-label">Community</div>
          <div className="dashboard-time-balance-value">
            {COMMUNITY.label}
          </div>
        </div>
      </aside>

      <main className="dashboard-main-content">
        <header className="dashboard-topbar">
          <div className="dashboard-topbar-title">
            <span className="dashboard-topbar-home">{title}</span>
            <span className="dashboard-topbar-dot">•</span>
            <span>Admin</span>
            <span className="dashboard-topbar-dot">•</span>
            <span>{COMMUNITY.shortLabel}</span>
          </div>
          <div className="dashboard-topbar-actions">
            <div className="notif-wrap">
              <button
                type="button"
                className="dashboard-icon-circle"
                aria-label="Notifications"
                onClick={() => setShowNotes((v) => !v)}
              >
                🔔
              </button>
              {showNotes ? (
                <div className="notif-panel">
                  <strong>Live notifications</strong>
                  {notifications.length === 0 ? (
                    <p>No new alerts.</p>
                  ) : (
                    notifications.map((note) => (
                      <button
                        key={note.id}
                        type="button"
                        className="notif-item"
                        onClick={() => setShowNotes(false)}
                      >
                        <span>{note.title}</span>
                        <small>{note.body}</small>
                      </button>
                    ))
                  )}
                </div>
              ) : null}
            </div>
            <div className="dashboard-top-user-avatar">{initials}</div>
            <button
              type="button"
              onClick={onLogout}
              className="dashboard-signout-btn"
            >
              Sign out
            </button>
          </div>
        </header>
        {children}
      </main>
    </div>
  );
};

export default PortalLayout;