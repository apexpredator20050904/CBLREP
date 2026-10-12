<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AdminMiddleware;
use App\Models\AdminTwoFactorChallenge;
use App\Models\AuditLog;
use App\Models\User;
use App\Support\TotpService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Second factor for the administrator console, by authenticator app (TOTP).
 *
 * The two-stage handshake:
 *
 *   1. POST /api/admin-login      -> (AuthController) primary credentials
 *                                    only, then one of two prompts, each
 *                                    issued with NO Sanctum token:
 *                                      - enrolled   → `requires_2fa` +
 *                                        challenge token
 *                                      - unenrolled → `requires_enrolment` +
 *                                        enrol token + ready-to-render QR
 *   2. POST /api/admin/2fa/verify          → enrolled: checks the code
 *      POST /api/admin/2fa/enrol/confirm   → unenrolled: proves the QR scan
 *      POST /api/admin/2fa/enrol/skip      → unenrolled: declines for now
 *                                            — and only these mint a token.
 *
 * Invariants worth defending in a review:
 *
 *  - Stage 1 never returns a usable token while a factor is outstanding, so
 *    skipping stage 2 gets an attacker nothing. The whole protection hinges
 *    on this, which is why the 2FA branch returns before `tokenResponse()`.
 *  - The code is never stored or compared as a secret. It is recomputed from
 *    the user's shared secret and the current time step inside TotpService,
 *    so a database dump does not yield a list of usable codes.
 *  - A challenge is bound to the browser that passed stage 1 via
 *    `challenge_token`, so a code shoulder-surfed in one tab cannot be
 *    redeemed from another machine.
 *  - A TOTP value stays valid for its whole 30-second step, so the same code
 *    is accepted twice unless something records that it was used. That is the
 *    `two_factor_last_used_at` guard, and it is the single most-missed
 *    property of naive TOTP implementations.
 *  - Failures are deliberately indistinguishable: a wrong code, an expired
 *    challenge and an unknown token all return the same 401 body, so the
 *    endpoint cannot be used as an oracle to enumerate valid challenges.
 */
class AdminTwoFactorController extends Controller
{
    /**
     * Uniform body for an enrolment token that is unknown, expired or spent.
     * Shared by enrolConfirm() and enrolSkip() so the two are indistinguishable
     * to a caller probing with junk tokens.
     */
    private const ENROL_EXPIRED = 'This setup session has expired. Please sign in again.';

    public function __construct(private readonly TotpService $totp) {}

    /**
     * Mint a stage-1 challenge and return the opaque token the browser must
     * echo back at stage 2.
     *
     * Public because AuthController drives stage 1, and kept here so the
     * challenge-lifecycle rules (supersede, hash, bind to browser) live in
     * exactly one place.
     *
     * No code is generated: with TOTP the "code" is computed on the phone
     * from a shared secret, so there is nothing to mail or store here. The
     * 64-character token is the only bearer secret this endpoint issues, it
     * is stored only as SHA-256, and it is worthless on its own.
     */
    public function issueChallenge(User $user, Request $request): string
    {
        // Rate-limit challenge issuance per account. Without this, the
        // supersede below hands an attacker a fresh 5-attempt budget on every
        // call: MAX_ATTEMPTS is per *challenge*, so re-running stage 1
        // resets it and the 1,000,000-code space becomes reachable over
        // hours rather than being capped at 5 per minute. The stage-1
        // credential check has already passed by the time we get here,
        // which is exactly why this ceiling lives on the account rather
        // than on the IP.
        //
        // The clock is read from `users.two_factor_challenge_issued_at`,
        // never from this table. An earlier version checked for a recent
        // challenge *row*, which the lockout path deletes — so burning a
        // challenge silently reset the cooldown. Measured against the
        // running app that yielded three full 5-guess rounds in seconds.
        $wait = $user->challengeCooldownRemaining();

        if ($wait > 0) {
            throw new HttpException(
                429,
                "A sign-in attempt was started moments ago. Please wait {$wait} more "
                .($wait === 1 ? 'second' : 'seconds').' before trying again.',
            );
        }

        // Supersede anything outstanding: only the newest challenge can be
        // redeemed, so an older token captured in transit is already inert.
        AdminTwoFactorChallenge::where('user_id', $user->id)->delete();

        $token = Str::random(64);

        AdminTwoFactorChallenge::create([
            'user_id' => $user->id,
            // Hashed at rest so a database dump cannot be replayed as a
            // live stage-2 session.
            'challenge_token' => hash('sha256', $token),
            'expires_at' => now()->addMinutes(AdminTwoFactorChallenge::TTL_MINUTES),
            'ip_address' => $request->ip(),
            'user_agent' => $request->userAgent(),
        ]);

        // Stamped only after the row exists, so a failed insert leaves the
        // account able to retry immediately instead of serving a 60-second
        // penalty for a challenge that was never created.
        $user->two_factor_challenge_issued_at = now();
        $user->save();

        return $token;
    }

    // ------------------------------------------------------------------
    // Login-time enrolment — the QR step for an admin with no authenticator
    // ------------------------------------------------------------------

    /**
     * Stage 1 for an administrator who has NOT enrolled yet: mint the
     * enrolment challenge and return everything the login screen needs to
     * render the QR code.
     *
     * Called by AuthController in the same situation as issueChallenge() —
     * password verified, no second factor — but for the not-yet-enrolled
     * branch. The token plays the same role (proves stage-1 credentials,
     * binds this pending enrolment to this browser), and the pending secret
     * is held in the same cache key as the Settings flow, so a half-finished
     * enrolment never touches the database and can never lock anyone out.
     *
     * Returns the whole payload rather than just the token because the
     * caller has no session and therefore cannot make a second
     * authenticated round-trip to fetch the QR.
     *
     * @return array{enrol_token: string, qr_code: string, secret: string, issuer: string, expires_in: int}
     */
    public function startLoginEnrolment(User $user, Request $request): array
    {
        // Issue the challenge FIRST: it carries the per-account issuance
        // cooldown and may reject with 429, and a rejected attempt must not
        // leave a pending secret sitting in cache.
        $token = $this->issueChallenge($user, $request);

        $secret = $this->totp->generateSecret();

        Cache::put($this->pendingKey($user->id), $secret, now()->addMinutes(15));

        return [
            'enrol_token' => $token,
            'qr_code' => $this->totp->qrCodeDataUri(
                $this->totp->provisioningUri($secret, $user->email),
            ),
            'secret' => $secret,
            'issuer' => TotpService::ISSUER,
            'expires_in' => AdminTwoFactorChallenge::TTL_MINUTES * 60,
        ];
    }

    /**
     * POST /api/admin/2fa/enrol/confirm — the first sign-in's stage 2:
     * prove the QR was scanned, switch the factor on, receive the session.
     *
     * The login-time twin of confirm(), with one structural difference:
     * authentication is the enrol_token (a SHA-256-hashed challenge issued
     * after the password check), not a Sanctum session — the administrator
     * does not have a token yet, which is the entire point of this flow.
     *
     * The pending secret is read from the cache, never from the request, so
     * the browser can only ever confirm a secret the server itself minted
     * for this account during this very sign-in.
     *
     * Wrong answers are deliberately 422/429, never 401: the shared axios
     * interceptor treats 401 as a dead session.
     */
    public function enrolConfirm(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'enrol_token' => ['required', 'string', 'size:64'],
            'code' => ['required', 'string', 'regex:/^\d{6}$/'],
        ], [
            'enrol_token.required' => self::ENROL_EXPIRED,
            'enrol_token.size' => self::ENROL_EXPIRED,
            'code.required' => 'Enter the 6-digit code shown in your authenticator app.',
            'code.regex' => 'Enter the 6-digit code shown in your authenticator app.',
        ]);

        $challenge = AdminTwoFactorChallenge::query()
            ->where('challenge_token', hash('sha256', $validated['enrol_token']))
            ->first();

        // Same uniform failure as verify(): no distinction between "no such
        // enrolment", "expired" and "already used".
        if (! $challenge || ! $challenge->isUsable()) {
            return $this->enrolmentExpired();
        }

        $user = $challenge->user;

        // The account may have been suspended or demoted while the QR sat on
        // screen — the scan proves possession of a phone, not entitlement.
        if (! $user || ! $user->isAdmin() || $user->account_status === 'suspended') {
            $challenge->delete();

            return response()->json([
                'message' => 'This account is no longer permitted to sign in.',
            ], 403);
        }

        $secret = Cache::get($this->pendingKey($user->id));

        if (! is_string($secret) || ! $this->totp->verify($secret, $validated['code'])) {
            $challenge->increment('attempts');

            if ($challenge->fresh()->isLockedOut()) {
                // Burn the pending secret along with the challenge: the QR on
                // screen is the other half of this enrolment and must not
                // stay confirmable once the token behind it is spent.
                $challenge->delete();
                Cache::forget($this->pendingKey($user->id));

                AuditLog::record(
                    $request,
                    '2FA enrolment destroyed after repeated wrong codes — '.$user->email,
                    'user',
                    $user->id,
                );

                return response()->json([
                    'message' => 'Too many incorrect codes. Please sign in again.',
                ], 429);
            }

            AuditLog::record(
                $request,
                'Failed 2FA enrolment confirmation at login — '.$user->email,
                'user',
                $user->id,
            );

            return response()->json([
                'message' => 'That code did not match. Check your app and enter the current code.',
            ], 422);
        }

        // Proof supplied. Recovery codes are minted before the factor flips,
        // exactly as in confirm(): never leave an account with a live
        // second factor and no way back in.
        [$codes, $digests] = $this->totp->generateRecoveryCodes();

        $user->two_factor_secret = $secret;
        // Clear the issuance clock before enableTwoFactor() saves: this
        // sign-in succeeded, so signing out and straight back in is
        // legitimate and must not trip the stage-1 issuance cooldown.
        $user->two_factor_challenge_issued_at = null;
        $user->enableTwoFactor($digests); // also deletes this user's challenges

        Cache::forget($this->pendingKey($user->id));

        AuditLog::record($request, 'Enabled authenticator 2FA during sign-in — '.$user->email, 'user', $user->id);

        return response()->json([
            'message' => 'Two-factor authentication is now active on this account.',
            'recovery_codes' => $codes,
            'access_token' => $user->createToken(AdminMiddleware::TWO_FACTOR_TOKEN)->plainTextToken,
            'token_type' => 'Bearer',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    /**
     * POST /api/admin/2fa/enrol/skip — abandon the QR step without enrolling.
     *
     * Keeps the opt-in model intact now that enrolment lives in the login
     * flow: an administrator without their phone at hand still reaches the
     * console, and Settings remains available to enrol later. Gated on the
     * enrol_token, so only the browser that passed the password check can
     * skip.
     *
     * Two things must happen together: the pending secret is destroyed (the
     * QR on screen becomes worthless) and the issuance clock is cleared (so
     * signing out and back in does not hit the stage-1 cooldown).
     */
    public function enrolSkip(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'enrol_token' => ['required', 'string', 'size:64'],
        ], [
            'enrol_token.required' => self::ENROL_EXPIRED,
            'enrol_token.size' => self::ENROL_EXPIRED,
        ]);

        $challenge = AdminTwoFactorChallenge::query()
            ->where('challenge_token', hash('sha256', $validated['enrol_token']))
            ->first();

        if (! $challenge || ! $challenge->isUsable()) {
            return $this->enrolmentExpired();
        }

        $user = $challenge->user;

        if (! $user || ! $user->isAdmin() || $user->account_status === 'suspended') {
            $challenge->delete();

            return response()->json([
                'message' => 'This account is no longer permitted to sign in.',
            ], 403);
        }

        // The QR shown during this sign-in must never become confirmable
        // afterwards — a walk-up at an unattended keyboard should not
        // inherit a half-finished enrolment.
        Cache::forget($this->pendingKey($user->id));

        $challenge->delete();
        $user->two_factor_challenge_issued_at = null;
        $user->save();

        AuditLog::record($request, 'Administrator skipped 2FA enrolment — '.$user->email, 'user', $user->id);

        // A plain admin token, not TWO_FACTOR_TOKEN: the account is still
        // unenrolled, so AdminMiddleware has no factor to demand. The moment
        // they DO enrol — here or in Settings — the confirm paths revoke this
        // one and mint a 2FA token instead.
        return response()->json([
            'access_token' => $user->createToken('cblrep-admin')->plainTextToken,
            'token_type' => 'Bearer',
            'user' => $user->toFrontendArray(),
        ]);
    }

    /** Uniform answer for "no such enrolment, expired, or already spent". */
    private function enrolmentExpired(): JsonResponse
    {
        return response()->json(['message' => self::ENROL_EXPIRED], 422);
    }

    /**
     * POST /api/admin/2fa/verify - redeem the code, receive the session.
     */
    public function verify(Request $request): JsonResponse
    {
        $validated = $request->validate(
            [
                'challenge_token' => ['required', 'string', 'size:64'],
                // Either a 6-digit TOTP value or a recovery code.
                // The recovery branch is XXXXX-XXXXX, matching
                // TotpService::randomRecoveryCode() (RECOVERY_LENGTH 10,
                // split 5/5 for legibility). These two must stay in step —
                // a mismatched length here silently makes every printed
                // recovery code unusable, since the codes are only ever
                // shown to the operator once.
                'code' => ['required', 'string', 'regex:/^(?:\d{6}|[A-Za-z0-9]{5}-[A-Za-z0-9]{5})$/'],
            ],
            [
                'challenge_token.required' => 'Your verification session has ended. Please sign in again.',
                'challenge_token.size' => 'Your verification session has ended. Please sign in again.',
                'code.required' => 'Enter the 6-digit code from your authenticator app, or a recovery code.',
                // Laravel's stock regex message renders as "The code field
                // format is invalid.", which reads poorly. "digits" is also
                // the rule a user would expect, so name it explicitly.
                'code.regex' => 'Enter the 6-digit code from your app, or a recovery code like A1B2-C3D4.',
            ],
        );

        $challenge = AdminTwoFactorChallenge::query()
            ->where('challenge_token', hash('sha256', $validated['challenge_token']))
            ->first();

        // Uniform failure: no distinction between "no such challenge",
        // "expired" and "already used". See the class docblock.
        if (! $challenge || ! $challenge->isUsable()) {
            return $this->invalidCode();
        }

        $user = $challenge->user;

        // The account may have been suspended or demoted while the code sat
        // on the operator's phone - the factor proves knowledge, not that the
        // account is still entitled to the console.
        if (! $user || ! $user->isAdmin() || $user->account_status === 'suspended') {
            $challenge->delete();

            return response()->json([
                'message' => 'This account is no longer permitted to sign in.',
            ], 403);
        }

        if ($this->totp->isReplayedCode($validated['code'], $user->two_factor_recent_codes)) {
            // The submitted value is byte-identical to the one already spent,
            // so this is a genuine replay rather than a mistyped code. Checked
            // before the code itself: spending the remaining attempt budget
            // here would punish a legitimate admin who double-submitted while
            // the clock was still inside the step.
            return $this->replayedCode();
        }

        // A recovery code is a single-use stand-in for a lost phone, so it is
        // accepted here on the same challenge and the same attempt budget.
        // Checked after the replay guard because it does not use the TOTP
        // time step, and before the TOTP compare so a code that happens to be
        // six digits is not misread as a TOTP value.
        $recovery = $this->totp->normaliseRecoveryCode($validated['code']);

        if (! ctype_digit($validated['code']) && $this->consumeRecoveryCode($user, $recovery)) {
            return $this->issueToken($user, $challenge, $request, recoveryUsed: true);
        }

        if (! $this->totp->verify($user->two_factor_secret, $validated['code'])) {
            $challenge->increment('attempts');

            if ($challenge->fresh()->isLockedOut()) {
                $challenge->delete();

                AuditLog::record(
                    $request,
                    '2FA challenge destroyed after repeated wrong codes — '.$user->email,
                    'user',
                    $user->id,
                );

                return response()->json([
                    'message' => 'Too many incorrect codes. Please sign in again.',
                ], 429);
            }

            return $this->invalidCode();
        }

        // Record this code as spent. Passing the code rather than a computed
        // list keeps one writer for the guard: issueToken() decides what
        // "spent" means and how the list is pruned, so the TOTP and recovery
        // paths cannot drift apart. Remembering every recent spend (not just
        // the newest) is what stops an earlier code being replayed inside the
        // verifier's tolerance window — exactly how T6 was reproduced.
        return $this->issueToken(
            $user,
            $challenge,
            $request,
            spentCode: $validated['code'],
        );
    }

    // ------------------------------------------------------------------
    // Enrolment — driven from the Settings screen by a signed-in admin
    // ------------------------------------------------------------------

    /**
     * POST /api/admin/2fa/setup — mint a secret and return the QR code.
     *
     * Deliberately does NOT enable anything. The secret is only persisted in
     * the cache, keyed by user id, until confirm() proves the admin actually
     * scanned it. Writing it to `users.two_factor_secret` here would leave a
     * half-configured factor on the row if the admin walked away, and any
     * later code that somehow matched would be accepted.
     *
     * Re-running this rotates the pending secret, so an abandoned setup
     * cannot be resurrected later from a stale QR code on screen.
     */
    public function setup(Request $request): JsonResponse
    {
        $user = $request->user();

        $secret = $this->totp->generateSecret();
        $uri = $this->totp->provisioningUri($secret, $user->email);

        Cache::put($this->pendingKey($user->id), $secret, now()->addMinutes(15));

        AuditLog::record($request, 'Started 2FA enrolment — '.$user->email, 'user', $user->id);

        return response()->json([
            'secret' => $secret,
            'qr_code' => $this->totp->qrCodeDataUri($uri),
            'provisioning_uri' => $uri,
            'issuer' => TotpService::ISSUER,
            'expires_in' => 15 * 60,
        ]);
    }

    /**
     * POST /api/admin/2fa/setup/confirm — verify a code and switch it on.
     *
     * The caller must be signed in (auth:sanctum) *and* pass a live code,
     * which is what proves the QR was genuinely scanned rather than merely
     * loaded into a page. There is no password re-entry here because the
     * request already carries a valid session token; a stolen session could
     * attach an attacker's own authenticator, but that session is already
     * compromised and this widens nothing that was not already lost.
     */
    public function confirm(Request $request): JsonResponse
    {
        $user = $request->user();

        $validated = $request->validate([
            'code' => ['required', 'string', 'regex:/^\d{6}$/'],
        ], [
            'code.regex' => 'Enter the 6-digit code shown in your authenticator app.',
        ]);

        $secret = Cache::get($this->pendingKey($user->id));

        if (! is_string($secret) || ! $this->totp->verify($secret, $validated['code'])) {
            AuditLog::record($request, 'Failed 2FA enrolment confirmation — '.$user->email, 'user', $user->id);

            return response()->json([
                'message' => 'That code did not match. Check your app and enter the current code.',
            ], 422);
        }

        // Recovery codes are generated before the factor is switched on, so
        // the admin is never left in a state where 2FA is live and a lost
        // phone means permanent lockout. The service returns
        // [plaintext, digests]; only the digests are persisted.
        [$codes, $digests] = $this->totp->generateRecoveryCodes();

        // The secret was kept in cache until this proof; only now does it
        // become the account's real enrolment.
        $user->two_factor_secret = $secret;
        $user->enableTwoFactor($digests);

        // The pending secret has served its purpose. Leaving it cached would
        // mean a replay of setup+confirm could re-activate a secret the
        // admin has since rotated away from.
        Cache::forget($this->pendingKey($user->id));

        // The account just became 2FA-protected, which invalidates the
        // session the admin enrolled with: AdminMiddleware refuses any token
        // not named TWO_FACTOR_TOKEN from here on, so the very next call from
        // the settings screen (fetchTwoFactorStatus) would 403 and strand
        // them on a screen that looks like it worked.
        //
        // Issuing a 2FA-verified token here is sound — the operator has just
        // proved possession of the authenticator by entering a live code, so
        // the second factor is satisfied, not assumed. The old token is
        // revoked rather than left alive, so enabling the factor never widens
        // the number of sessions in play.
        $this->currentToken($request)?->delete();

        $token = $user->createToken(AdminMiddleware::TWO_FACTOR_TOKEN)->plainTextToken;

        AuditLog::record($request, 'Enabled authenticator 2FA — '.$user->email, 'user', $user->id);

        return response()->json([
            'message' => 'Two-factor authentication is now active on this account.',
            'recovery_codes' => $codes,
            'access_token' => $token,
            'token_type' => 'Bearer',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    /**
     * The PersonalAccessToken backing this request, or null when the guard
     * did not resolve one (stateful cookie auth). Used only to revoke, so a
     * null is safe to ignore.
     */
    private function currentToken(Request $request): ?PersonalAccessToken
    {
        $token = $request->user()?->currentAccessToken();

        return $token instanceof PersonalAccessToken ? $token : null;
    }
    /**
     * POST /api/admin/2fa/disable — turn the factor off.
     *
     * Requires the account password. Without that check, a hijacked console
     * session could strip 2FA and then persist, turning a temporary
     * compromise into a permanent one.
     */
    public function disable(Request $request): JsonResponse
    {
        $user = $request->user();

        $validated = $request->validate([
            'password' => ['required', 'string'],
            'code' => ['required', 'string', 'regex:/^\d{6}$/'],
        ], [
            'code.regex' => 'Enter the 6-digit code shown in your authenticator app.',
        ]);

        // Password checked before the code so a wrong password costs no
        // TOTP attempt against the replay window.
        if (! Hash::check($validated['password'], $user->password)) {
            AuditLog::record($request, 'Failed 2FA disable (bad password) — '.$user->email, 'user', $user->id);

            return response()->json(['message' => 'Your password is incorrect.'], 422);
        }

        if (! $this->totp->verify((string) $user->two_factor_secret, $validated['code'])) {
            AuditLog::record($request, 'Failed 2FA disable (bad code) — '.$user->email, 'user', $user->id);

            return response()->json([
                'message' => 'That code did not match. Enter the current code from your app.',
            ], 422);
        }

        $user->disableTwoFactor();

        AuditLog::record($request, 'Disabled 2FA — '.$user->email, 'user', $user->id);

        return response()->json(['message' => 'Two-factor authentication has been turned off.']);
    }

    /**
     * POST /api/admin/2fa/recovery-codes — issue a fresh set.
     *
     * Password-gated like disable(): regenerating replaces the only way back
     * in after a lost phone, so it must not be a one-click action for anyone
     * holding a borrowed session.
     */
    public function regenerateRecoveryCodes(Request $request): JsonResponse
    {
        $user = $request->user();

        $validated = $request->validate([
            'password' => ['required', 'string'],
            'code' => ['required', 'string', 'regex:/^\d{6}$/'],
        ], [
            'code.regex' => 'Enter the 6-digit code shown in your authenticator app.',
        ]);

        if (! Hash::check($validated['password'], $user->password)
            || ! $this->totp->verify((string) $user->two_factor_secret, $validated['code'])) {
            AuditLog::record($request, 'Failed 2FA recovery-code regeneration — '.$user->email, 'user', $user->id);

            return response()->json([
                'message' => 'Your password or verification code is incorrect.',
            ], 422);
        }

        [$plaintext, $digests] = $this->totp->generateRecoveryCodes();

        // forceFill is required: the column is encrypted and deliberately not
        // on $fillable, so a plain mass-assign would be silently dropped.
        $user->forceFill(['two_factor_recovery_codes' => $digests])->save();

        AuditLog::record($request, 'Regenerated 2FA recovery codes — '.$user->email, 'user', $user->id);

        return response()->json([
            'message' => 'Your previous recovery codes are no longer valid.',
            'recovery_codes' => $plaintext,
        ]);
    }

    /**
     * GET /api/admin/2fa/status — what the Settings screen needs to render.
     */
    public function status(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'enabled' => $user->hasEnrolledTwoFactor(),
            'confirmed_at' => $user->two_factor_confirmed_at?->toIso8601String(),
            'recovery_codes_remaining' => $user->recoveryCodeCount(),
        ]);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /**
     * Burn a matching recovery code and drop it from the stored digests.
     *
     * Single-use is the whole point: a code transcribed onto paper and left
     * in a drawer must be worthless to anyone who finds it later.
     */
    private function consumeRecoveryCode(User $user, string $candidate): bool
    {
        $digests = $user->recoveryCodeDigests();

        if ($digests === [] || ! $this->totp->matchesRecoveryCode($candidate, $digests)) {
            return false;
        }

        $winner = $this->totp->digestRecoveryCode($candidate);

        $user->forceFill([
            'two_factor_recovery_codes' => array_values(array_filter(
                $digests,
                fn ($digest) => ! hash_equals((string) $digest, $winner),
            )),
        ])->save();

        return true;
    }

    /**
     * Consume the challenge and mint the console session.
     *
     * The challenge row is deleted rather than flagged, so a captured
     * challenge token plus a valid code still cannot be replayed into a
     * second token.
     */
    private function issueToken(
        User $user,
        AdminTwoFactorChallenge $challenge,
        Request $request,
        bool $recoveryUsed = false,
        ?string $spentCode = null,
    ): JsonResponse {
        $challenge->delete();

        // Clear the issuance clock — this login succeeded, so the account is
        // no longer mid-challenge. Without this, a legitimate re-login inside
        // the cooldown window is 429'd by issueChallenge() for a code it does
        // not actually need. Clearing is safe on every success path: the only
        // way to reach this method is to have produced a correct TOTP or
        // recovery code, which is exactly what an attacker farming fresh
        // attempt budgets cannot do, so it grants them nothing.
        $columns = ['two_factor_challenge_issued_at' => null];

        // The replay guard is stamped only for the TOTP path. A recovery code
        // is not bound to a time step, so recording one would make the guard
        // treat a later, perfectly valid 6-digit code as a replay.
        //
        // The digest list is stored rather than a single value: keeping only
        // the newest code made every older code inside the verify window
        // replayable, because spending a newer code overwrote the only record
        // the guard consulted.
        if (! $recoveryUsed) {
            $columns['two_factor_last_used_at'] = now();
        }

        if ($spentCode !== null) {
            $columns['two_factor_recent_codes'] = $this->totp->rememberSpentCode(
                $user->two_factor_recent_codes,
                $spentCode,
            );
        }

        $user->forceFill($columns)->save();

        AuditLog::record(
            $request,
            'Administrator completed 2FA sign-in'.($recoveryUsed ? ' (recovery code)' : '').' — '.$user->email,
            'user',
            $user->id,
        );

        return response()->json([
            'access_token' => $user->createToken(AdminMiddleware::TWO_FACTOR_TOKEN)->plainTextToken,
            'token_type' => 'Bearer',
            'user' => $user->toFrontendArray(),
            'recovery_code_used' => $recoveryUsed,
            'recovery_codes_remaining' => $user->recoveryCodeCount(),
        ]);
    }

    /** Where the un-confirmed secret waits during enrolment. */
    private function pendingKey(int $userId): string
    {
        return 'admin:2fa:pending:'.$userId;
    }

    /** The single response every unusable-challenge case funnels through. */
    private function invalidCode(): JsonResponse
    {
        return response()->json([
            'message' => 'That verification code is invalid. Check your authenticator app and try again.',
        ], 401);
    }

    /**
     * Replay gets its own message because the remedy differs: wait for the
     * next code rather than retyping the current one. A generic "invalid"
     * would send a legitimate admin into an endless retry loop.
     */
    private function replayedCode(): JsonResponse
    {
        return response()->json([
            'message' => 'That code was already used. Wait for your app to show the next code.',
        ], 429);
    }
}
