import { useCallback, useState } from "react";
import PortalLayout from "./layouts/PortalLayout";
import { COMMUNITY, communityLocation } from "./config/community";
import { apiFetch } from "./admin/api";
import "./admin.css";
import OverviewPage from "./admin/OverviewPage";
import UsersPage from "./admin/UsersPage";
import VerificationPage from "./admin/VerificationPage";
import ResourcesPage from "./admin/ResourcesPage";
import ExchangesPage from "./admin/ExchangesPage";
import ReportsPage from "./admin/ReportsPage";
import AdminMapPage from "./admin/AdminMapPage";
import AnalyticsPage from "./admin/AnalyticsPage";
import SettingsPage from "./admin/SettingsPage";
import AuditLogsPage from "./admin/AuditLogsPage";

const EX_TAB_TYPE = {
  admin_exchanges: "all",
  ex_freecycle: "freecycling",
  ex_barter: "bartering",
  ex_lend: "lending",
  ex_timebank: "timebank",
};

const AdminApp = ({ user, onLogout }) => {
  const [activeTab, setActiveTab] = useState("overview");
  const [toast, setToast] = useState("");

  const showToast = useCallback((msg) => {
    setToast(msg);
    setTimeout(() => setToast(""), 3000);
  }, []);

  // Refresh dashboard counters after moderation/user actions land elsewhere.
  const reloadDashboard = useCallback(async () => {
    try {
      await apiFetch("/api/admin/dashboard");
    } catch {
      /* counters refresh on next visit */
    }
  }, []);

  const userName = user?.fullName || "Administrator";
  const location = communityLocation(user?.barangay) || COMMUNITY.label;
  const initials = userName
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  const content = () => {
    switch (activeTab) {
      case "users":
        return <UsersPage mode="all" showToast={showToast} />;
      case "suspended":
        return <UsersPage mode="suspended" showToast={showToast} />;
      case "verification":
        return <VerificationPage showToast={showToast} />;
      case "admin_listings":
        return <ResourcesPage kind="all" showToast={showToast} />;
      case "listings_offers":
        return <ResourcesPage kind="offers" showToast={showToast} />;
      case "listings_needs":
        return <ResourcesPage kind="needs" showToast={showToast} />;
      case "listings_flagged":
        return <ResourcesPage kind="flagged" showToast={showToast} />;
      case "admin_exchanges":
      case "ex_freecycle":
      case "ex_barter":
      case "ex_lend":
      case "ex_timebank":
        return (
          <ExchangesPage
            type={EX_TAB_TYPE[activeTab] || "all"}
            showToast={showToast}
          />
        );
      case "reports":
        return (
          <ReportsPage showToast={showToast} reloadDashboard={reloadDashboard} />
        );
      case "map":
        return <AdminMapPage showToast={showToast} />;
      case "analytics":
        return <AnalyticsPage showToast={showToast} />;
      case "logs":
        return <AuditLogsPage showToast={showToast} />;
      case "settings":
        return <SettingsPage showToast={showToast} />;
      default:
        return <OverviewPage onNavigate={setActiveTab} />;
    }
  };

  return (
    <PortalLayout
      userName={userName}
      barangayName={location}
      initials={initials}
      activeTab={activeTab}
      onNavigate={(tab) => {
        setActiveTab(tab);
        window.history.replaceState(null, "", `/admin/${tab}`);
      }}
      onLogout={onLogout}
    >
      {toast ? <div className="admin-toast">{toast}</div> : null}
      {content()}
    </PortalLayout>
  );
};

export default AdminApp;
