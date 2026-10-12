// ─────────────────────────────────────────────────────────────
// CBLRE Admin · App entry — admin-only router
// ─────────────────────────────────────────────────────────────
// Standalone admin console for Trinidad, Bohol (municipal + barangay
// managers). There are deliberately NO public/member screens here — the
// Flutter mobile app serves members. The app boots at /login (Admin
// Login); every /admin/* route is wrapped in <RequireAdmin> (RBAC guard).
//
// Routes:
//   /login                  Admin Login (public, sole entry)
//   /admin                  Dashboard overview (summary cards)
//   /admin/verification     Trinidad resident + barangay verification
//   /admin/users            All users (suspend / reactivate)
//   /admin/listings         All resource listings (moderation)
//   /admin/listings/offers  Offers only
//   /admin/listings/needs   Needs only
//   /admin/listings/flagged Flagged listings
//   /admin/exchanges         Exchanges (existing backend)
//   /admin/notifications      Notifications & announcements (NEW)
//   /admin/content            Content management (NEW)
//   /admin/reports            Reports & moderation (existing backend)
//   /admin/analytics        Municipal analytics + CSV/PDF export
//   /admin/audit-logs       Immutable admin audit trail
//   /admin/settings         Municipal settings (existing backend)
//   *                       → /login (unknown paths bounce to entry)
// ─────────────────────────────────────────────────────────────
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import RequireAdmin from "./components/RequireAdmin";
import ErrorBoundary from "./components/ErrorBoundary";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import VerificationPage from "./pages/VerificationPage";
import UsersPage from "./pages/UsersPage";
import ListingsPage from "./pages/ListingsPage";
import MapPage from "./pages/MapPage";
import InquiriesPage from "./pages/InquiriesPage";
import ExchangesPage from "./pages/ExchangesPage";
import BarterRequestsPage from "./pages/BarterRequestsPage";
import NotificationsPage from "./pages/NotificationsPage";
import ContentPage from "./pages/ContentPage";
import ReportsPage from "./pages/ReportsPage";
import AnalyticsPage from "./pages/AnalyticsPage";
import AuditLogsPage from "./pages/AuditLogsPage";
import SettingsPage from "./pages/SettingsPage";
import { useEffect } from "react";

function ThemePreference() {
  useEffect(() => {
    const theme = localStorage.getItem("cblrep_admin_theme") || "light";
    document.documentElement.classList.toggle("dark", theme === "dark");
  }, []);
  return null;
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <ThemePreference />
        <Routes>
          {/* Sole public screen — admin sign-in */}
          <Route path="/login" element={<LoginPage />} />

          {/* Protected admin console (RBAC-guarded, error-isolated per tab) */}
          <Route element={<RequireAdmin />}>
            <Route path="/admin" element={<ErrorBoundary><DashboardPage /></ErrorBoundary>} />
            <Route path="/admin/verification" element={<ErrorBoundary><VerificationPage /></ErrorBoundary>} />
            <Route path="/admin/users" element={<ErrorBoundary><UsersPage /></ErrorBoundary>} />
            <Route path="/admin/listings" element={<ErrorBoundary><ListingsPage kind="all" /></ErrorBoundary>} />
            <Route path="/admin/map" element={<ErrorBoundary><MapPage /></ErrorBoundary>} />
            <Route path="/admin/listings/offers" element={<ErrorBoundary><ListingsPage kind="offers" /></ErrorBoundary>} />
            <Route path="/admin/listings/needs" element={<ErrorBoundary><ListingsPage kind="needs" /></ErrorBoundary>} />
            <Route path="/admin/listings/flagged" element={<ErrorBoundary><ListingsPage kind="flagged" /></ErrorBoundary>} />
            <Route path="/admin/inquiries" element={<ErrorBoundary><InquiriesPage /></ErrorBoundary>} />
            <Route path="/admin/exchanges" element={<ErrorBoundary><ExchangesPage /></ErrorBoundary>} />
            <Route path="/admin/barter-requests" element={<ErrorBoundary><BarterRequestsPage /></ErrorBoundary>} />
            <Route path="/admin/notifications" element={<ErrorBoundary><NotificationsPage /></ErrorBoundary>} />
            <Route path="/admin/content" element={<ErrorBoundary><ContentPage /></ErrorBoundary>} />
            <Route path="/admin/reports" element={<ErrorBoundary><ReportsPage /></ErrorBoundary>} />
            <Route path="/admin/analytics" element={<ErrorBoundary><AnalyticsPage /></ErrorBoundary>} />
            <Route path="/admin/audit-logs" element={<ErrorBoundary><AuditLogsPage /></ErrorBoundary>} />
            <Route path="/admin/settings" element={<ErrorBoundary><SettingsPage /></ErrorBoundary>} />
          </Route>

          {/* Default + fallback: always land on admin login */}
          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
