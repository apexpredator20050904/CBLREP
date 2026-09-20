/* eslint-disable react-refresh/only-export-components */
// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Auth context + RBAC guard primitives
// ─────────────────────────────────────────────────────────────
// Centralises the Sanctum session (token + admin profile) so every admin
// route can rely on one source of truth. Persisted to localStorage so a
// page refresh keeps the admin signed in; re-validated against Laravel
// (GET /user) on app boot — a stale/forged token is dropped and the admin
// is bounced to /login by the RequireAdmin route guard.
// ─────────────────────────────────────────────────────────────
import { createContext, useCallback, useContext, useEffect, useState } from "react";
import {
  adminLogin as apiAdminLogin,
  adminLogout as apiAdminLogout,
  clearStoredSession,
  fetchCurrentAdmin,
  getStoredUser,
  getToken,
} from "../services/adminApi";
import { isAdminUser } from "../config/community";

const AuthContext = createContext(null);

/** Provider — mount once at the root (see App.jsx). */
export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => getStoredUser());
  const [initialising, setInitialising] = useState(true);

  // On boot: if a token exists, re-validate it against Laravel.
  useEffect(() => {
    const token = getToken();
    if (!token) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setInitialising(false);
      return;
    }
    fetchCurrentAdmin()
      .then((fresh) => {
        // Belt-and-braces: even with a valid token, non-admins stay out.
        if (!isAdminUser(fresh)) {
          clearStoredSession();
          setUser(null);
        } else {
          setUser(fresh);
        }
      })
      .catch(() => {
        clearStoredSession();
        setUser(null);
      })
      .finally(() => setInitialising(false));
  }, []);

  const login = useCallback(async (credentials) => {
    const data = await apiAdminLogin(credentials);
    if (!isAdminUser(data.user)) {
      clearStoredSession();
      setUser(null);
      throw new Error("This account does not have administrator access.");
    }
    setUser(data.user);
    return data.user;
  }, []);

  const logout = useCallback(async () => {
    await apiAdminLogout();
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        login,
        logout,
        isAuthenticated: !!user && !!getToken(),
        isAdmin: isAdminUser(user),
        initialising,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

/** Hook for consuming the admin session in pages/layout. */
export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
}
