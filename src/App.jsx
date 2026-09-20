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
//   /admin/analytics        Municipal analytics + CSV/PDF export
//   /admin/audit-logs       Immutable admin audit trail
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
import AnalyticsPage from "./pages/AnalyticsPage";
import AuditLogsPage from "./pages/AuditLogsPage";

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
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
            <Route path="/admin/analytics" element={<AnalyticsPage />} />
            <Route path="/admin/audit-logs" element={<AuditLogsPage />} />
          </Route>

          {/* Default + fallback: always land on admin login */}
          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}

