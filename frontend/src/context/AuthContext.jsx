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
  confirmLoginEnrolment as apiConfirmEnrolment,
  fetchCurrentAdmin,
  getStoredUser,
  getToken,
  skipLoginEnrolment as apiSkipEnrolment,
  verifyAdminTwoFactor as apiVerifyTwoFactor,
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

  /**
   * Stage 1. Resolves to a prompt descriptor when a second step is
   * outstanding, in which case NO session exists yet and the caller must
   * render the matching UI. Otherwise returns the user.
   *
   *   - `requiresTwoFactor: true`   → enrolled: render the code prompt
   *   - `requiresEnrolment: true`   → unenrolled: render the QR enrolment
   *     step (payload includes the QR data-URI and manual key)
   *
   * There is no `emailHint`: a TOTP code is produced on the operator's own
   * device, so there is no mailbox to point them at.
   */
  const login = useCallback(async (credentials) => {
    const data = await apiAdminLogin(credentials);

    if (data.requires_2fa) {
      // Deliberately no session is written here. The Sanctum token is minted
      // only by completeTwoFactor(), so an abandoned prompt cannot leave the
      // admin half-authenticated.
      return {
        requiresTwoFactor: true,
        challengeToken: data.challenge_token,
        expiresIn: data.expires_in,
        qrCode: data.qr_code,
        secret: data.secret,
        issuer: data.issuer,
      };
    }

    if (data.requires_enrolment) {
      // First sign-in: server minted a QR but NO token. The session comes
      // only from completeEnrolment() (code confirmed) or skipEnrolment()
      // (declined) — rendering the QR must not authenticate anyone.
      return {
        requiresEnrolment: true,
        enrolToken: data.enrol_token,
        qrCode: data.qr_code,
        secret: data.secret,
        issuer: data.issuer,
        expiresIn: data.expires_in,
      };
    }

    if (!isAdminUser(data.user)) {
      clearStoredSession();
      setUser(null);
      throw new Error("This account does not have administrator access.");
    }
    setUser(data.user);
    return { requiresTwoFactor: false, user: data.user };
  }, []);

  /**
   * Stage 2. Redeems the authenticator (or recovery) code and only then
   * establishes the session. See login() for why stage 1 mints nothing.
   */
  const completeTwoFactor = useCallback(async (challengeToken, code) => {
    const data = await apiVerifyTwoFactor({ challengeToken, code });

    if (!isAdminUser(data.user)) {
      clearStoredSession();
      setUser(null);
      throw new Error("This account does not have administrator access.");
    }
    setUser(data.user);
    return data.user;
  }, []);

  /**
   * Login-time enrolment, confirm half. Redeems the code scanned from the
   * QR and returns the user plus the one-time recovery codes.
   *
   * Deliberately does NOT call setUser(): the recovery-code screen must be
   * shown before the session becomes visible, or LoginPage's top-of-file
   * guard would redirect to /admin on the very next render and the operator
   * would never see the only copy of those codes. adoptSession() flips the
   * switch once they have been acknowledged. The token itself is already
   * persisted by the API layer, so nothing is lost on a mid-flow reload —
   * the codes can be re-issued from Settings if that happens.
   */
  const completeEnrolment = useCallback(async (enrolToken, code) => {
    const data = await apiConfirmEnrolment({ enrolToken, code });

    if (!isAdminUser(data.user)) {
      clearStoredSession();
      throw new Error("This account does not have administrator access.");
    }
    return { user: data.user, recoveryCodes: data.recovery_codes ?? [] };
  }, []);

  /**
   * Make an already-persisted session visible to the app. Used once the
   * login-time recovery-code screen has been acknowledged.
   */
  const adoptSession = useCallback((user) => {
    if (!isAdminUser(user)) {
      clearStoredSession();
      setUser(null);
      throw new Error("This account does not have administrator access.");
    }
    setUser(user);
    return user;
  }, []);

  /**
   * Login-time enrolment, skip half: password-only session. The pending QR
   * is destroyed server-side, and Settings remains available for enrolling
   * later.
   */
  const skipEnrolment = useCallback(async (enrolToken) => {
    const data = await apiSkipEnrolment({ enrolToken });

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
        completeTwoFactor,
        completeEnrolment,
        adoptSession,
        skipEnrolment,
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
