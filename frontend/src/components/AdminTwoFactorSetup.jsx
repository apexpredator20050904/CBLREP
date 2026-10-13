import { useEffect, useRef, useState } from "react";
import { beginTwoFactorSetup, confirmTwoFactorSetup, disableTwoFactor, fetchTwoFactorStatus, regenerateRecoveryCodes } from "../services/adminApi";
import { btnGhost, btnPrimary } from "./ui";

/**
 * Enrolment + management panel for authenticator-app 2FA.
 *
 * Three states, driven by the server's `enabled` flag:
 *
 *   off  → a "Set up" button that mints a secret and reveals the QR
 *   on   → status, recovery-code count, regenerate and disable controls
 *
 * Between off and on sits `pending`: the secret exists only in the server's
 * 15-minute cache until a live code proves the QR was actually scanned. That
 * proof is what stops someone enrolling a factor onto an account they have
 * merely walked up to at an unattended machine.
 */
export default function TwoFactorSetup({ onChanged }) {
  const [status, setStatus] = useState(null);
  const [enrolment, setEnrolment] = useState(null); // { secret, qr_code, issuer }
  const [code, setCode] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState(null);
  const [disablePassword, setDisablePassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  // The confirm field is autofocused on reveal; on a phone the OS keyboard
  // then opens straight onto the code box, which is the whole point of the step.
  const codeRef = useRef(null);

  useEffect(() => {
    fetchTwoFactorStatus()
      .then(setStatus)
      .catch((e) => setError(e.message));
  }, []);

  useEffect(() => {
    if (enrolment) codeRef.current?.focus();
  }, [enrolment]);

  const begin = async () => {
    setBusy(true);
    setError("");
    setNotice("");
    setRecoveryCodes(null);
    try {
      setEnrolment(await beginTwoFactorSetup());
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  /** Abandons a half-finished enrolment and discards the on-screen secret. */
  const cancelEnrolment = () => {
    setEnrolment(null);
    setCode("");
  };

  const confirm = async (event) => {
    event.preventDefault();
    if (code.replace(/\D/g, "").length !== 6) {
      setError("Enter the 6-digit code currently shown in your app.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const result = await confirmTwoFactorSetup(code);
      // The codes are shown exactly once — the server keeps only digests,
      // so there is no second chance to read them.
      setRecoveryCodes(result.recovery_codes);
      setEnrolment(null);
      setCode("");
      setStatus(await fetchTwoFactorStatus());
      onChanged?.();
    } catch (e) {
      setError(e.message);
      setCode("");
      codeRef.current?.focus();
    } finally {
      setBusy(false);
    }
  };

  const regenerate = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      const result = await regenerateRecoveryCodes({ password: disablePassword, code });
      setRecoveryCodes(result.recovery_codes);
      setCode("");
      setDisablePassword("");
      setStatus(await fetchTwoFactorStatus());
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const turnOff = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await disableTwoFactor({ password: disablePassword, code });
      setDisablePassword("");
      setCode("");
      setStatus(await fetchTwoFactorStatus());
      setNotice("Two-factor authentication is now off on this account.");
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  if (status === null) {
    return <p className="text-sm text-stone-500">Loading two-factor status…</p>;
  }

  // ── Recovery codes: shown once, right after enrolment or regeneration ──
  //
  // This branch deliberately takes over the whole panel. The codes are the
  // only copy the operator will ever get, so nothing else on the screen is
  // allowed to compete with them for attention.
  if (recoveryCodes) {
    return (
      <div className="space-y-4">
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4">
          <p className="font-semibold text-amber-900">Save these recovery codes now</p>
          <p className="mt-1 text-sm text-amber-800">
            Each code works once if you ever lose access to your authenticator. They are shown
            only this time — the server stores just a hash of each, so it cannot show them again.
          </p>
        </div>

        <ul className="grid grid-cols-2 gap-2 rounded-lg bg-stone-50 p-4 font-mono text-sm sm:grid-cols-3">
          {recoveryCodes.map((c) => (
            <li key={c} className="select-all rounded bg-white px-2 py-1 text-center text-stone-800">
              {c}
            </li>
          ))}
        </ul>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => {
              navigator.clipboard?.writeText(recoveryCodes.join("\n"));
              setNotice("Recovery codes copied to the clipboard.");
            }}
            className={btnGhost}
          >
            📋 Copy all
          </button>
          <button type="button" onClick={() => window.print()} className={btnGhost}>
            🖨 Print
          </button>
          <button type="button" onClick={() => setRecoveryCodes(null)} className={btnPrimary}>
            I have saved them
          </button>
        </div>
      </div>
    );
  }
  // ── Enrolment in progress: secret minted, awaiting proof of a live code ──
  if (enrolment) {
    return (
      <form onSubmit={confirm} className="space-y-5">
        <ol className="list-inside list-decimal space-y-1 text-sm text-stone-600">
          <li>Open your authenticator app (Google Authenticator, Authy, Bitwarden…).</li>
          <li>Scan the QR code below using its camera icon.</li>
          <li>Enter the 6-digit code it shows to finish setup.</li>
        </ol>

        <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-start">
          <img
            src={enrolment.qr_code}
            alt="QR code containing the authenticator setup key"
            className="h-48 w-48 rounded-lg border border-stone-200 bg-white p-2"
          />

          <div className="flex-1 space-y-3">
            <div>
              <p className="text-xs font-bold uppercase tracking-wide text-stone-500">
                Can&apos;t scan? Enter this key manually
              </p>
              {/* select-all so a double-click copies the whole secret, which is
                  what someone typing it into a desktop app actually needs. */}
              <p className="mt-1 select-all break-all rounded-lg bg-stone-50 p-3 font-mono text-sm text-stone-800">
                {enrolment.secret}
              </p>
              <p className="mt-1 text-xs text-stone-500">
                Issuer: <span className="font-mono">{enrolment.issuer}</span> · Type: Time-based
              </p>
            </div>

            <div>
              <label htmlFor="totp-enrol-code" className="block text-sm font-semibold text-stone-700">
                6-digit code from your app
              </label>
              <input
                id="totp-enrol-code"
                ref={codeRef}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                placeholder="000000"
                className="mt-1 w-40 rounded-lg border border-stone-300 px-3 py-2 text-center font-mono text-lg tracking-[0.3em] focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-100"
              />
            </div>
          </div>
        </div>

        {error && <p role="alert" className="text-sm font-medium text-red-700">{error}</p>}

        <div className="flex gap-2">
          <button type="submit" disabled={busy} className={btnPrimary}>
            {busy ? "Verifying…" : "Verify & enable"}
          </button>
          <button type="button" onClick={cancelEnrolment} disabled={busy} className={btnGhost}>
            Cancel
          </button>
        </div>

        <p className="text-xs text-stone-500">
          This setup expires in 15 minutes. Cancelling discards the key — starting over issues
          a new one, and the abandoned secret can never be enrolled.
        </p>
      </form>
    );
  }

  // ── Not yet enrolled ──
  if (!status.enabled) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-stone-600">
          This account currently signs in with a password alone. Adding an authenticator app
          means a stolen password on its own is not enough to reach the admin console.
        </p>
        {error && <p role="alert" className="text-sm font-medium text-red-700">{error}</p>}
        {notice && <p className="text-sm font-medium text-emerald-700">{notice}</p>}
        <button type="button" onClick={begin} disabled={busy} className={btnPrimary}>
          {busy ? "Preparing…" : "🔐 Set up authenticator app"}
        </button>
      </div>
    );
  }

  // ── Enrolled: status + identity-confirmed sensitive operations ──
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3">
        <span className="font-bold text-emerald-700">✓</span>
        <p className="text-sm font-semibold text-emerald-900">
          Two-factor authentication is active on this account.
        </p>
      </div>

      <p className="text-sm text-stone-600">
        {status.recovery_codes_remaining} recovery code{status.recovery_codes_remaining === 1 ? "" : "s"} remaining
        {status.confirmed_at
          ? ` · enabled ${new Date(status.confirmed_at).toLocaleDateString()}`
          : ""}
        . Regenerating issues a new set and immediately invalidates the old one.
      </p>

      <details className="rounded-lg border border-stone-200 p-4">
        <summary className="cursor-pointer text-sm font-semibold text-stone-700">
          Sensitive actions — confirm your identity
        </summary>

        <div className="mt-3 space-y-3">
          <p className="text-xs text-stone-500">
            Disabling the factor or reissuing recovery codes both require your password
            <em> and</em> a current code, so a hijacked session alone cannot strip your own
            protection off.
          </p>

          <div>
            <label htmlFor="totp-sens-pass" className="block text-sm font-medium text-stone-700">
              Current password
            </label>
            <input
              id="totp-sens-pass"
              type="password"
              value={disablePassword}
              onChange={(e) => setDisablePassword(e.target.value)}
              autoComplete="current-password"
              className="mt-1 w-full max-w-xs rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-100"
            />
          </div>

          <div>
            <label htmlFor="totp-sens-code" className="block text-sm font-medium text-stone-700">
              Current 6-digit code
            </label>
            <input
              id="totp-sens-code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              placeholder="000000"
              className="mt-1 w-40 rounded-lg border border-stone-300 px-3 py-2 text-center font-mono tracking-[0.3em] focus:border-emerald-600 focus:outline-none focus:ring-2 focus:ring-emerald-100"
            />
          </div>

          {error && <p role="alert" className="text-sm font-medium text-red-700">{error}</p>}
          {notice && <p className="text-sm font-medium text-emerald-700">{notice}</p>}

          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={regenerate} disabled={busy} className={btnGhost}>
              Regenerate recovery codes
            </button>
            <button
              type="button"
              onClick={turnOff}
              disabled={busy}
              className="rounded-lg border border-red-200 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 disabled:opacity-60"
            >
              Turn off two-factor
            </button>
          </div>
        </div>
      </details>
    </div>
  );
}
