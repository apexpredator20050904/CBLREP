import { useEffect, useRef, useState } from "react";

/**
 * AdminLoginEnrolment — the QR step shown after the password passes when the
 * administrator has no authenticator enrolled yet. The login-flow twin of
 * Settings' AdminTwoFactorSetup.
 *
 * It receives NO session and makes no API calls itself: the parent's handlers
 * own those (exactly as AdminTwoFactorModal delegates to onVerify), so the
 * place a session comes into existence stays in one layer — AuthContext.
 *
 * Two phases: "setup" (QR + manual key + 6-digit input) then "codes" (the
 * one-time recovery codes). AuthContext holds the session back until
 * "Continue", because LoginPage's guard would otherwise redirect past the
 * codes screen — and they are shown only once.
 *
 * "Skip for now" signs in with the password alone and destroys the QR
 * server-side; Settings remains available for enrolling later.
 */
export default function AdminLoginEnrolment({
  qrCode,
  secret,
  issuer,
  expiresIn = 600,
  onConfirm,
  onSkip,
  onFinish,
  onCancel,
}) {
  const [phase, setPhase] = useState("setup"); // "setup" | "codes"
  const [code, setCode] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState([]);
  const [enrolledUser, setEnrolledUser] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  // Seconds until the enrol token expires — the QR is worthless without it.
  const [remaining, setRemaining] = useState(Math.floor(expiresIn) || 600);
  const [expired, setExpired] = useState(false);

  const inputRef = useRef(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    const id = setInterval(() => {
      setRemaining((s) => {
        if (s <= 1) {
          setExpired(true);
          return 0;
        }
        return s - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, []);

  const handleSubmit = async (e) => {
    e?.preventDefault();
    if (busy || expired) return;

    if (code.length !== 6) {
      setError("Enter the complete 6-digit code from your authenticator app.");
      return;
    }

    setBusy(true);
    setError("");
    try {
      // Delegated — the parent (via AuthContext) owns the API call.
      const result = await onConfirm(code);
      setCode("");
      setRecoveryCodes(result.recoveryCodes);
      setEnrolledUser(result.user);
      setPhase("codes");
    } catch (err) {
      setError(err.message);
      setCode("");
      inputRef.current?.focus();
    } finally {
      setBusy(false);
    }
  };

  const handleSkip = async () => {
    if (busy || expired) return;
    setBusy(true);
    setError("");
    try {
      await onSkip(); // parent navigates on success; stay busy until then
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  const mm = String(Math.floor(remaining / 60)).padStart(2, "0");
  const ss = String(remaining % 60).padStart(2, "0");

  // ── Phase 2: the one-time recovery codes ──────────────────────────
  // Takes over the whole overlay: these codes are the only copy that will
  // ever exist, so nothing else may compete for attention.
  if (phase === "codes") {
    return (
      <div
        className="fixed inset-0 z-50 flex items-center justify-center bg-emerald-950/70 p-4 backdrop-blur-sm"
        role="dialog"
        aria-modal="true"
        aria-labelledby="enrol-codes-title"
      >
        <div className="w-full max-w-lg rounded-2xl border border-stone-200 bg-white p-8 shadow-2xl">
          <div className="flex items-start gap-4">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-800 text-lg">
              ✅
            </span>
            <div>
              <h2 id="enrol-codes-title" className="text-xl font-extrabold text-emerald-950">
                Save your recovery codes
              </h2>
              <p className="mt-1 text-sm text-stone-500">
                Two-factor authentication is now active on this account.
              </p>
            </div>
          </div>

          <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-4">
            <p className="font-semibold text-amber-900">Each code works exactly once</p>
            <p className="mt-1 text-sm text-amber-800">
              If you ever lose access to your authenticator, a recovery code is the only way
              back in. They are shown only this time — the server stores just a hash of each.
            </p>
          </div>

          <ul className="mt-4 grid grid-cols-2 gap-2 rounded-lg bg-stone-50 p-4 font-mono text-sm sm:grid-cols-3">
            {recoveryCodes.map((c) => (
              <li key={c} className="select-all rounded bg-white px-2 py-1 text-center text-stone-800">
                {c}
              </li>
            ))}
          </ul>

          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => navigator.clipboard?.writeText(recoveryCodes.join("\n"))}
              className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold text-stone-700 hover:bg-stone-50"
            >
              📋 Copy all
            </button>
            <button
              type="button"
              onClick={() => window.print()}
              className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold text-stone-700 hover:bg-stone-50"
            >
              🖨 Print
            </button>
          </div>

          <button
            type="button"
            onClick={() => onFinish(enrolledUser)}
            className="mt-5 w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-bold text-white hover:bg-emerald-900"
          >
            I have saved them — continue to console
          </button>
        </div>
      </div>
    );
  }
  // ── Phase 1: QR + code entry ──────────────────────────────────────
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-emerald-950/70 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="enrol-title"
    >
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-lg rounded-2xl border border-stone-200 bg-white p-8 shadow-2xl"
      >
        <div className="flex items-start gap-4">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-800 text-lg">
            🔐
          </span>
          <div>
            <h2 id="enrol-title" className="text-xl font-extrabold text-emerald-950">
              Set up your authenticator
            </h2>
            <p className="mt-1 text-sm text-stone-500">
              One quick step — scan this code with your authenticator extension, then enter
              the 6-digit code it shows.
            </p>
          </div>
        </div>

        <ol className="mt-4 list-inside list-decimal space-y-1 text-sm text-stone-600">
          <li>Open your authenticator extension (Google Authenticator, Authy, Bitwarden…).</li>
          <li>Scan the QR code below, or type the key manually.</li>
          <li>Enter the 6-digit code it shows to finish signing in.</li>
        </ol>

        <div className="mt-4 flex flex-col gap-4 sm:flex-row sm:items-start">
          <img
            src={qrCode}
            alt="QR code containing your two-factor setup key"
            className="h-44 w-44 shrink-0 rounded-lg border border-stone-200 bg-white p-2"
          />

          <div className="flex-1 space-y-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-wide text-stone-500">
                Can&apos;t scan? Enter this key manually
              </p>
              {/* select-all so a double-click copies the whole secret, which is
                  what someone typing it into a desktop extension actually needs. */}
              <p className="mt-1 select-all break-all rounded-lg bg-stone-50 p-2 font-mono text-sm text-stone-800">
                {secret}
              </p>
              <p className="mt-1 text-xs text-stone-500">
                Issuer: <span className="font-mono">{issuer}</span> · Type: Time-based
              </p>
            </div>

            <div>
              <label htmlFor="login-enrol-code" className="block text-sm font-semibold text-stone-700">
                6-digit code from your app
              </label>
              <input
                id="login-enrol-code"
                ref={inputRef}
                value={code}
                onChange={(e) => {
                  setCode(e.target.value.replace(/\D/g, "").slice(0, 6));
                  setError("");
                }}
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                placeholder="000000"
                disabled={busy || expired}
                aria-invalid={Boolean(error)}
                className="mt-1 w-40 rounded-lg border border-stone-300 px-3 py-2 text-center font-mono text-lg tracking-[0.3em] focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-100"
              />
            </div>
          </div>
        </div>

        {error && (
          <p role="alert" className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
            {error}
          </p>
        )}

        {expired && (
          <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-xs font-medium text-amber-800">
            This setup session has expired. Go back and sign in again — a fresh QR will be
            generated for you.
          </p>
        )}

        <button
          type="submit"
          disabled={busy || expired}
          className="mt-5 w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-bold text-white hover:bg-emerald-900 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {busy ? "⏳ Verifying…" : "Verify & continue"}
        </button>

        <div className="mt-4 flex items-center justify-between text-xs">
          <span className="font-medium text-stone-500">
            {expired ? "Setup expired" : `Setup expires in ${mm}:${ss}`} · codes refresh every
            30s
          </span>
          <button
            type="button"
            onClick={handleSkip}
            disabled={busy || expired}
            className="font-semibold text-emerald-700 hover:text-emerald-900 disabled:cursor-not-allowed disabled:text-stone-400"
          >
            Skip for now
          </button>
        </div>

        <div className="mt-3 flex items-center justify-between text-xs">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="text-stone-500 hover:text-stone-700 disabled:opacity-60"
          >
            Back to sign in
          </button>
        </div>

        <p className="mt-4 border-t border-stone-200 pt-4 text-center text-[11px] leading-relaxed text-stone-400">
          Skipping leaves your account protected by your password alone — you can enrol later
          from Settings → Account security.
        </p>
      </form>
    </div>
  );
}
