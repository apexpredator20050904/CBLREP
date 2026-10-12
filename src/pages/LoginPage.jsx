// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Admin Login (entry point of the app)
// ─────────────────────────────────────────────────────────────
// The ONLY public screen. Verifies credentials via POST /admin-login
// (AuthContext.login), which rejects non-admin accounts even when the
// password is correct. On success, react-router navigates to /admin.
// ─────────────────────────────────────────────────────────────
import { useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import logo from "../assets/logo.jpg";
import AdminLoginEnrolment from "../components/AdminLoginEnrolment";
import AdminTwoFactorModal from "../components/AdminTwoFactorModal";
import { useAuth } from "../context/AuthContext";

export default function LoginPage() {
  const { user, isAdmin, login, completeTwoFactor, completeEnrolment, adoptSession, skipEnrolment } =
    useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({ email: "", password: "" });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  // Stage-2 challenge. Non-null only after the password has been accepted and
  // the account is flagged two_factor_enabled. Holding the token here (not in
  // AuthContext state) keeps it from leaking into any component that reads
  // the session, and it is discarded the moment the operator backs out.
  const [challenge, setChallenge] = useState(null);

  // Login-time enrolment. Set after the password has been accepted and the
  // account has NO authenticator yet — carries the QR payload the overlay
  // renders. Mutually exclusive with `challenge` (an account is either
  // enrolled or not), and, like it, discarded on cancel.
  const [enrolment, setEnrolment] = useState(null);

  // Already signed in as admin → skip straight to the dashboard.
  if (user && isAdmin) return <Navigate to="/admin" replace />;

  const onChange = (e) =>
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const onSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      const result = await login(form);

      if (result.requiresTwoFactor) {
        // Password accepted but NOT signed in. Show the QR + code prompt; the
        // Sanctum token does not exist yet, so leaving this screen cannot
        // strand the operator in a half-authenticated state.
        setChallenge({
          token: result.challengeToken,
          expiresIn: result.expiresIn,
          qrCode: result.qrCode,
          secret: result.secret,
          issuer: result.issuer,
        });
        return;
      }

      if (result.requiresEnrolment) {
        // Password accepted, no authenticator enrolled yet: show the QR step
        // right here in the login flow. The session is created only once the
        // operator confirms a scanned code (or explicitly skips).
        setEnrolment({
          token: result.enrolToken,
          qrCode: result.qrCode,
          secret: result.secret,
          issuer: result.issuer,
          expiresIn: result.expiresIn,
        });
        return;
      }

      navigate("/admin", { replace: true });
    } catch (err) {
      setError(err.message || "Unable to sign in as admin.");
    } finally {
      setBusy(false);
    }
  };

  // Stage 2 resolved — the session now exists in AuthContext, so the guard at
  // the top of this component redirects on the next render.
  const onVerified = () => navigate("/admin", { replace: true });

  return (
    <div className="flex min-h-screen bg-emerald-950">
      {/* Brand panel */}
      <div className="hidden w-2/5 flex-col justify-between bg-emerald-900 p-10 text-white lg:flex">
        <div className="flex items-center gap-3">
          <img src={logo} alt="CBLREP logo" className="h-12 w-12 rounded-full object-cover" />
          <div>
            <p className="font-extrabold tracking-wide">CBLREP · ADMIN CONSOLE</p>
            <p className="text-sm text-emerald-200/70">Trinidad, Bohol</p>
          </div>
        </div>
        <div>
          <h1 className="text-3xl font-extrabold leading-tight">
            Municipal resource governance for Trinidad.
          </h1>
          <p className="mt-3 text-sm text-emerald-100/80">
            Verify residents per barangay, moderate Offers &amp; Needs, and export
            municipal analytics — all from one console.
          </p>
        </div>
        <p className="text-xs text-emerald-200/60">
          Restricted access · all login attempts are logged and monitored.
        </p>
      </div>

      {/* Login form */}
      <div className="flex flex-1 items-center justify-center bg-stone-50 p-6">
        <form
          onSubmit={onSubmit}
          className="w-full max-w-md rounded-2xl border border-stone-200 bg-white p-8 shadow-xl"
        >
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-800 text-lg">
              🛡️
            </span>
            <div>
              <h2 className="text-xl font-extrabold text-emerald-950">System Administrator</h2>
              <p className="text-sm text-stone-500">Restricted access — verified admins only</p>
            </div>
          </div>

          <label className="mt-6 block text-sm font-semibold text-stone-700">
            Administrator Email
            <input
              type="email"
              name="email"
              value={form.email}
              onChange={onChange}
              placeholder="name@example.com"
              required
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-600 focus:outline-none"
            />
          </label>

          <label className="mt-4 block text-sm font-semibold text-stone-700">
            Password
            <input
              type="password"
              name="password"
              value={form.password}
              onChange={onChange}
              placeholder="Administrator password"
              required
              className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-600 focus:outline-none"
            />
          </label>

          {error ? (
            <p className="mt-4 rounded-lg bg-red-50 px-3 py-2 text-sm font-medium text-red-700">
              {error}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={busy}
            className="mt-6 w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-bold text-white hover:bg-emerald-900 disabled:opacity-60"
          >
            {busy ? "Signing in…" : "Sign In as Administrator"}
          </button>
        </form>
      </div>

      {/*
        Stage 2. Rendered only once a challenge exists. The modal calls
        completeTwoFactor() itself, then onVerified() navigates onward; the
        `onCancel` path drops the token so backing out invalidates it locally
        and the operator is returned to a clean password form.
      */}
      {challenge && (
        <AdminTwoFactorModal
          challengeToken={challenge.token}
          expiresIn={challenge.expiresIn}
          qrCode={challenge.qrCode}
          secret={challenge.secret}
          issuer={challenge.issuer}
          onVerify={(code) => completeTwoFactor(challenge.token, code)}
          onVerified={onVerified}
          onCancel={() => {
            setChallenge(null);
            setForm({ email: "", password: "" });
            setError("");
          }}
        />
      )}

      {/*
        Login-time enrolment. Rendered only once the password has passed and
        the account has no authenticator. onConfirm returns the user plus the
        one-time recovery codes WITHOUT making the session visible (the guard
        at the top of this component would redirect past the codes screen);
        onFinish adopts the session only after they have been acknowledged.
        Cancel drops the enrol token, so the QR on screen is abandoned and
        expires server-side on its own.
      */}
      {enrolment && (
        <AdminLoginEnrolment
          qrCode={enrolment.qrCode}
          secret={enrolment.secret}
          issuer={enrolment.issuer}
          expiresIn={enrolment.expiresIn}
          onConfirm={(code) => completeEnrolment(enrolment.token, code)}
          onSkip={async () => {
            await skipEnrolment(enrolment.token);
            onVerified();
          }}
          onFinish={(enrolled) => {
            adoptSession(enrolled);
            onVerified();
          }}
          onCancel={() => {
            setEnrolment(null);
            setForm({ email: "", password: "" });
            setError("");
          }}
        />
      )}
    </div>
  );
}
