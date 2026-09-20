// ─────────────────────────────────────────────────────────────
// CBLRE Admin · RBAC route guard
// ─────────────────────────────────────────────────────────────
// <RequireAdmin> wraps every /admin/* route. Three states:
//   1. initialising (token re-validation) → loading splash, no redirect yet
//      so a refresh doesn't flash the login screen.
//   2. no session / non-admin user → <Navigate to="/login" replace />
//   3. verified admin → render the protected page via <Outlet />.
// Non-admin members holding a valid token are still bounced: the municipal
// console is exclusively for system administrators / barangay managers.
// ─────────────────────────────────────────────────────────────
import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

export default function RequireAdmin() {
  const { isAuthenticated, isAdmin, initialising } = useAuth();

  if (initialising) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-stone-100">
        <p className="text-sm font-medium text-stone-500">
          Verifying administrator session…
        </p>
      </div>
    );
  }

  if (!isAuthenticated || !isAdmin) {
    return <Navigate to="/login" replace />;
  }

  return <Outlet />;
}
