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
//   /admin/timebank           Time Bank (existing backend)
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
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import VerificationPage from "./pages/VerificationPage";
import UsersPage from "./pages/UsersPage";
import ListingsPage from "./pages/ListingsPage";
import ExchangesPage from "./pages/ExchangesPage";
import TimeBankPage from "./pages/TimeBankPage";
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

          {/* Protected admin console (RBAC-guarded) */}
          <Route element={<RequireAdmin />}>
            <Route path="/admin" element={<DashboardPage />} />
            <Route path="/admin/verification" element={<VerificationPage />} />
            <Route path="/admin/users" element={<UsersPage />} />
            <Route path="/admin/listings" element={<ListingsPage kind="all" />} />
            <Route path="/admin/listings/offers" element={<ListingsPage kind="offers" />} />
            <Route path="/admin/listings/needs" element={<ListingsPage kind="needs" />} />
            <Route path="/admin/listings/flagged" element={<ListingsPage kind="flagged" />} />
            <Route path="/admin/exchanges" element={<ExchangesPage />} />
            <Route path="/admin/timebank" element={<TimeBankPage />} />
            <Route path="/admin/notifications" element={<NotificationsPage />} />
            <Route path="/admin/content" element={<ContentPage />} />
            <Route path="/admin/reports" element={<ReportsPage />} />
            <Route path="/admin/analytics" element={<AnalyticsPage />} />
            <Route path="/admin/audit-logs" element={<AuditLogsPage />} />
            <Route path="/admin/settings" element={<SettingsPage />} />
          </Route>

          {/* Default + fallback: always land on admin login */}
          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
