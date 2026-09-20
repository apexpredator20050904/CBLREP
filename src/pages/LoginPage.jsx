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
import { useAuth } from "../context/AuthContext";

export default function LoginPage() {
  const { user, isAdmin, login } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({ email: "", password: "", adminCode: "" });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  // Already signed in as admin → skip straight to the dashboard.
  if (user && isAdmin) return <Navigate to="/admin" replace />;

  const onChange = (e) =>
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const onSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      await login(form);
      navigate("/admin", { replace: true });
    } catch (err) {
      setError(err.message || "Unable to sign in as admin.");
    } finally {
      setBusy(false);
    }
  };

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
              placeholder="admin@cblrep.ph"
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

          <label className="mt-4 block text-sm font-semibold text-stone-700">
            Admin Access Code{" "}
            <span className="font-normal text-stone-400">(optional for demo)</span>
            <input
              type="text"
              name="adminCode"
              value={form.adminCode}
              onChange={onChange}
              placeholder="6-digit code from authenticator"
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
    </div>
  );
}
