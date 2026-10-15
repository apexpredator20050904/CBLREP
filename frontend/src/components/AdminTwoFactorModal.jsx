import { useCallback, useEffect, useRef, useState } from "react";

/** TOTP rotation period in seconds — Google Authenticator's default. */
const PERIOD = 30;

/** Seconds since the epoch, floored to the current TOTP window. */
const windowIndex = () => Math.floor(Date.now() / 1000 / PERIOD);

/**
 * AdminTwoFactorModal — stage 2 of administrator sign-in (authenticator app).
 *
 * Appears once POST /admin-login has confirmed the password but the account
 * has an enrolled authenticator, and is the only step that can mint the
 * Sanctum token. It deliberately receives no `user` prop: the parent has no
 * session yet, and showing a name here would imply more trust than has been
 * proven.
 *
 * Two phases when a QR code is provided (browser authenticator extension):
 *   1. "scan"  — display the QR code for the extension to scan
 *   2. "verify" — 6-digit code input (the existing UI)
 *
 * When no QR code is provided, the modal opens directly in "verify" phase.
 *
 * Security/UX notes:
 *  - Verification is delegated to the parent's `onVerify`, not performed here.
 *    Redeeming the code is what mints the session, so AuthContext must be the
 *    thing that calls setUser(). If this component called the API directly the
 *    token would land in localStorage while `user` stayed null, and the
 *    <RequireAdmin> guard would bounce a fully-authenticated admin back to
 *    the login screen. Keeping the parent in charge means there is exactly
 *    one place a session comes into existence.
 *  - There is deliberately NO "resend" button. A TOTP code is computed on the
 *    operator's own device from the shared secret; the server never sends
 *    anything, so there is nothing to resend. The only dead end is a lost
 *    phone, and that is what recovery codes exist for.
 *  - The six boxes are one input. Six real <input>s invite paste and autofill
 *    bugs and let a stray character land in the wrong box; this draws visual
 *    cells over a single controlled field instead.
 *  - The code never outlives this modal and is cleared on close, on success,
 *    and on every failure.
 *  - `autoComplete="one-time-code"` lets iOS/Android offer the code from the
 *    notification without weakening anything.
 */
export default function AdminTwoFactorModal({
  expiresIn = 600,
  qrCode,
  secret,
  issuer,
  onVerify,
  onVerified,
  onCancel,
}) {
  // Phase: "scan" shows the QR code, "verify" shows the code input.
  const [phase, setPhase] = useState(qrCode ? "scan" : "verify");

  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);

  // Recovery codes are the escape hatch for a lost or wiped device. Toggled
  // into view rather than offered as a second tab, so the primary path stays
  // the 6-digit code and the alternative does not compete for attention.
  const [useRecovery, setUseRecovery] = useState(false);

  // Which TOTP window the code ring currently sits in, and how long is left
  // of it. Re-rendered every second so the operator can see when to retype.
  const [window_, setWindow_] = useState(windowIndex());
  const [periodLeft, setPeriodLeft] = useState(PERIOD);

  // Seconds until the *challenge* expires, shown as a live countdown. This is
  // separate from the 30s code window: the code rotates constantly, but the
  // chance to submit one is capped.
  const [remaining, setRemaining] = useState(Math.floor((expiresIn || 600) / 1000) || 600);
  const [expired, setExpired] = useState(false);

  const inputRef = useRef(null);

  // Focus the field on mount so the operator can type straight away.
  useEffect(() => {
    if (phase === "verify") inputRef.current?.focus();
  }, [phase]);

  // Expiry countdown.
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

  // TOTP window ticker. Drives both the "next code in Ns" hint and the
  // boundary flag, so the operator can be told to retype instead of
  // discovering a stale code through a 401.
  useEffect(() => {
    const tick = () => {
      const now = Math.floor(Date.now() / 1000);
      setWindow_(Math.floor(now / PERIOD));
      setPeriodLeft(PERIOD - (now % PERIOD));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  // Clear a code the moment its window closes. Re-submitting a code the
  // server has already rejected is the most common self-inflicted 401 here:
  // the operator types as the ring rolls over and the code is already stale.
  useEffect(() => {
    // Synchronous setState is intentional: this responds to the window
    // rolling over (every 30s), not to mount, so there is no render cascade.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCode((c) => (useRecovery || c.length < 6 ? c : ""));
  }, [window_, useRecovery]);

  // Digits only, max 6 for a TOTP; recovery codes are typed as
  // "A1B2-C3D4" and filtered to 8 alphanumerics, letting the dash through
  // so the operator sees the grouping they were given.
  const handleChange = (e) => {
    const raw = e.target.value;
    setCode(
      useRecovery
        ? raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8)
        : raw.replace(/\D/g, "").slice(0, 6)
    );
    setError("");
  };

  const handleSubmit = useCallback(
    async (e) => {
      e?.preventDefault();
      if (busy || expired) return;

      const length = useRecovery ? 8 : 6;
      if (code.length !== length) {
        setError(
          useRecovery
            ? "Enter one of your recovery codes (8 characters, e.g. A1B2-C3D4)."
            : "Enter the complete 6-digit code from your authenticator app."
        );
        return;
      }

      setBusy(true);
      setError("");
      setNotice("");

      try {
        // Delegated — see the note on onVerify above.
        const session = await onVerify(code);
        setCode(""); // scrub before handing control back
        onVerified(session);
      } catch (err) {
        setError(err.message);
        setCode("");
        inputRef.current?.focus();
      } finally {
        setBusy(false);
      }
    },
    [busy, code, expired, onVerify, onVerified, useRecovery]
  );

  // Toggling between TOTP and recovery-code entry clears whatever was typed,
  // so a 6-digit string can never be submitted through the 8-character path.
  const handleToggleRecovery = useCallback(() => {
    setUseRecovery((v) => !v);
    setCode("");
    setError("");
    setNotice("");
    inputRef.current?.focus();
  }, []);

  const handleClose = useCallback(() => {
    setCode("");
    onCancel();
  }, [onCancel]);

  const mm = String(Math.floor(remaining / 60)).padStart(2, "0");
  const ss = String(remaining % 60).padStart(2, "0");

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-emerald-950/70 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="twofa-title"
    >
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-md rounded-2xl border border-stone-200 bg-white p-8 shadow-2xl"
      >
        {/* ── Phase 1: QR Code Scan ─────────────────────────────── */}
        {phase === "scan" && (
          <>
            <div className="flex items-start gap-4">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-800 text-lg">
                📱
              </span>
              <div>
                <h2 id="twofa-title" className="text-xl font-extrabold text-emerald-950">
                  Scan with Authenticator
                </h2>
                <p className="mt-1 text-sm text-stone-500">
                  Use your browser authenticator extension to scan this QR code.
                </p>
              </div>
            </div>

            <div className="mt-6 flex flex-col items-center">
              <div className="rounded-2xl border-2 border-emerald-200 bg-white p-4">
                <img
                  src={qrCode}
                  alt="TOTP QR code for authenticator app"
                  className="h-52 w-52"
                />
              </div>

              <div className="mt-4 w-full rounded-lg bg-stone-50 px-4 py-3">
                <p className="text-xs font-semibold text-stone-500">Manual entry key</p>
                <p className="mt-1 font-mono text-sm font-bold tracking-wider text-emerald-950">
                  {secret}
                </p>
                <p className="mt-1 text-xs text-stone-400">
                  Issuer: {issuer}
                </p>
              </div>
            </div>

            <div className="mt-5 flex items-center justify-between text-xs">
              <span className="font-medium text-stone-500">Session expires in</span>
              <span
                className={
                  expired
                    ? "font-bold text-red-600"
                    : remaining <= 60
                      ? "font-bold text-amber-600"
                      : "font-mono font-medium text-stone-500"
                }
              >
                {expired ? "Expired" : `${mm}:${ss}`}
              </span>
            </div>

            <button
              type="button"
              onClick={() => {
                setPhase("verify");
                setError("");
                setNotice("");
              }}
              className="mt-6 w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-bold text-white hover:bg-emerald-900"
            >
              I&apos;ve scanned it — enter code
            </button>

            <button
              type="button"
              onClick={handleClose}
              className="mt-3 w-full rounded-lg border border-stone-300 py-2.5 text-sm font-semibold text-stone-600 hover:bg-stone-50"
            >
              Back to sign in
            </button>
          </>
        )}

        {/* ── Phase 2: Code Verification ────────────────────────── */}
        {phase === "verify" && (
          <>
            <div className="flex items-start gap-4">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-800 text-lg">
                🔐
              </span>
              <div>
                <h2 id="twofa-title" className="text-xl font-extrabold text-emerald-950">
                  {useRecovery ? "Recovery Code" : "Two-Factor Verification"}
                </h2>
                <p className="mt-1 text-sm text-stone-500">
                  {useRecovery
                    ? "Enter one of the single-use recovery codes you saved during setup."
                    : "Open your authenticator app and enter the current 6-digit code."}
                </p>
              </div>
            </div>

            {/*
              Live countdown to the next code. A TOTP is only valid inside its
              30-second window, so showing the ring lets the operator time their
              typing instead of discovering the rollover as a failed sign-in.
            */}
            {!useRecovery && !expired && (
              <div className="mt-4 flex items-center gap-3 rounded-lg bg-emerald-50 px-3 py-2">
                <svg viewBox="0 0 36 36" className="h-8 w-8 shrink-0 -rotate-90" aria-hidden="true">
                  <circle
                    cx="18" cy="18" r="15.5" fill="none" stroke="#a7f3d0" strokeWidth="3"
                  />
                  <circle
                    cx="18" cy="18" r="15.5" fill="none" stroke="#047857" strokeWidth="3"
                    strokeLinecap="round"
                    strokeDasharray={`${(periodLeft / PERIOD) * 97.4} 97.4`}
                  />
                </svg>
                <p className="text-xs text-emerald-900">
                  Code refreshes in{" "}
                  <span className="font-bold tabular-nums">{periodLeft}s</span>
                </p>
              </div>
            )}

            <div className="mt-5 flex items-center justify-between text-xs">
              <span className="font-medium text-stone-500">
                {useRecovery ? "Recovery code" : "Verification code"}
              </span>
              <span
                className={
                  expired
                    ? "font-bold text-red-600"
                    : remaining <= 60
                      ? "font-bold text-amber-600"
                      : "font-mono font-medium text-stone-500"
                }
              >
                {expired ? "Expired" : `Session expires in ${mm}:${ss}`}
              </span>
            </div>

            {/* Single input, visual cells drawn over it. */}
            <div className="relative mt-2">
              <input
                ref={inputRef}
                type="text"
                inputMode={useRecovery ? "text" : "numeric"}
                autoComplete={useRecovery ? "off" : "one-time-code"}
                maxLength={useRecovery ? 9 : 6}
                value={useRecovery ? code.replace(/(.{4})/, "$1-") : code}
                onChange={handleChange}
                disabled={busy || expired}
                aria-label={useRecovery ? "Recovery code" : "6-digit verification code"}
                aria-invalid={Boolean(error)}
                className="absolute inset-0 h-full w-full cursor-pointer bg-transparent text-transparent caret-transparent outline-none disabled:cursor-not-allowed"
              />
              <div className="pointer-events-none flex gap-2" aria-hidden="true">
                {Array.from({ length: useRecovery ? 8 : 6 }, (_, i) => {
                  const active = i === code.length;
                  return (
                    <div
                      key={i}
                      className={[
                        "flex h-12 flex-1 items-center justify-center rounded-lg border text-lg font-bold transition",
                        error
                          ? "border-red-300 text-red-600"
                          : active
                            ? "border-emerald-600 bg-emerald-50 text-emerald-900 ring-2 ring-emerald-200"
                            : code[i]
                              ? "border-emerald-600 bg-emerald-50 text-emerald-900"
                              : "border-stone-300 bg-stone-50 text-stone-400",
                      ].join(" ")}
                    >
                      {code[i] || ""}
                    </div>
                  );
                })}
              </div>
            </div>

            {error && (
              <p
                role="alert"
                className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-red-700"
              >
                {error}
              </p>
            )}
            {notice && !error && (
              <p
                role="status"
                className="mt-3 rounded-lg bg-emerald-50 px-3 py-2 text-xs font-medium text-emerald-800"
              >
                {notice}
              </p>
            )}

            {expired && (
              <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-xs font-medium text-amber-800">
                This sign-in attempt has expired. Return to the login screen and start again —
                your authenticator is not affected.
              </p>
            )}

            <button
              type="submit"
              disabled={busy || expired}
              className="mt-6 w-full rounded-lg bg-emerald-800 py-2.5 text-sm font-bold text-white hover:bg-emerald-900 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {busy ? "⏳ Verifying…" : "Verify & Sign In"}
            </button>

            <div className="mt-4 flex items-center justify-between text-xs">
              <button
                type="button"
                onClick={handleToggleRecovery}
                disabled={busy}
                className="font-semibold text-emerald-700 hover:text-emerald-900 disabled:cursor-not-allowed disabled:text-stone-400"
              >
                {useRecovery ? "Use authenticator code" : "Use a recovery code"}
              </button>
              <button
                type="button"
                onClick={handleClose}
                disabled={busy}
                className="text-stone-500 hover:text-stone-700 disabled:opacity-60"
              >
                Back to sign in
              </button>
            </div>

            <p className="mt-5 border-t border-stone-200 pt-4 text-center text-[11px] leading-relaxed text-stone-400">
              If you did not attempt to sign in, no action is needed. The attempt expires on
              its own and no session was created.
            </p>
          </>
        )}
      </form>
    </div>
  );
}
