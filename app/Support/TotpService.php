<?php

namespace App\Support;

use BaconQrCode\Renderer\Image\SvgImageBackEnd;
use BaconQrCode\Renderer\ImageRenderer;
use BaconQrCode\Renderer\RendererStyle\RendererStyle;
use BaconQrCode\Writer;
use DateTimeImmutable;
use DateTimeInterface;
use PragmaRX\Google2FA\Exceptions\InvalidCharactersException;
use PragmaRX\Google2FA\Exceptions\SecretKeyTooShortException;
use PragmaRX\Google2FA\Google2FA;

/**
 * Authenticator-app TOTP for the admin console.
 *
 * Wraps pragmarx/google2fa and bacon/bacon-qr-code so the controllers never
 * touch either library directly. Keeping the crypto in one place means the
 * drift window, the secret lifetime and the replay rule are decided once.
 *
 * Package choice is deliberate. The commonly-recommended
 * pragmarx/google2fa-laravel is a thin wrapper unmaintained for years and
 * pinned to google2fa v7; this uses v8 directly. On the QR side, most PHP QR
 * libraries render through GD or Imagick — neither extension is present on
 * this host — so we take BaconQrCode's pure SVG back end, which needs no
 * image extension and never hands a rasteriser untrusted input.
 */
class TotpService
{
    /** Issuer shown in the authenticator app. Must match `issuer` in the URI. */
    public const ISSUER = 'CBLREP Trinidad';

    /**
     * Time steps of drift tolerated either side of "now".
     *
     * One step = ±30s, covering ordinary server/phone clock drift without
     * meaningfully widening the window. Each extra step multiplies the
     * guessable space, so this is deliberately not 2.
     */
    private const WINDOW = 1;

    /** Base32 characters per secret. 16 chars = 80 bits of entropy. */
    private const SECRET_LENGTH = 16;

    /** Characters in a generated recovery code. */
    private const RECOVERY_LENGTH = 10;

    /**
     * Alphabet for recovery codes.
     *
     * Visually ambiguous glyphs (0/O, 1/I/L) are omitted on purpose — these
     * get read off a screen and typed by hand, and a mistyped 0-for-O is a
     * locked-out administrator with no recourse.
     */
    private const RECOVERY_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    /**
     * How long an already-accepted code stays unusable.
     *
     * A TOTP value is valid for its whole 30-second step, so without this an
     * attacker who shoulder-surfs a code has up to 60s of overlap (the step
     * plus the tolerated drift window) to replay it. Covering that span means
     * each observed code is good for exactly one sign-in.
     */
    private const REPLAY_GUARD_SECONDS = 90;

    private Google2FA $engine;

    public function __construct()
    {
        $this->engine = new Google2FA;

        // Reject secrets some authenticator apps mishandle, so a key
        // generated here is guaranteed importable rather than discovered
        // broken at the moment the admin tries to scan it.
        $this->engine->setEnforceGoogleAuthenticatorCompatibility(true);
        $this->engine->setWindow(self::WINDOW);
    }

    /** Mint a fresh base32 shared secret. */
    public function generateSecret(): string
    {
        return $this->engine->generateSecretKey(self::SECRET_LENGTH);
    }

    /**
     * The otpauth:// URI an authenticator app consumes.
     *
     * `issuer` appears twice by design: once as a path segment and once as a
     * query parameter. Google Authenticator ignores the latter, other apps
     * ignore the former — including both is the interoperable convention.
     */
    public function provisioningUri(string $secret, string $accountEmail): string
    {
        return $this->engine->getQRCodeUrl(self::ISSUER, $accountEmail, $secret);
    }

    /**
     * Render the provisioning URI as an inline SVG data URI.
     *
     * Inline rather than a PNG endpoint for two reasons: no image extension
     * is required, and the QR is drawn from a URI we generated ourselves —
     * the browser never calls a third-party chart API with a live secret in
     * the query string, which would hand that secret to the third party.
     */
    public function qrCodeDataUri(string $provisioningUri): string
    {
        $renderer = new ImageRenderer(
            // 220px with a 2-module quiet zone. The margin is required by
            // the QR spec and is what lets scanners cope with screen glare.
            new RendererStyle(220, 2),
            new SvgImageBackEnd,
        );

        $svg = (new Writer($renderer))->writeString($provisioningUri);

        return 'data:image/svg+xml;base64,'.base64_encode($svg);
    }

    /**
     * Check a 6-digit code against the secret.
     *
     * Returns false rather than throwing on a malformed secret or key, so a
     * corrupt row degrades into a rejected sign-in instead of a 500.
     */
    public function verify(string $secret, string $code): bool
    {
        if ($secret === '' || ! preg_match('/^\d{6}$/', $code)) {
            return false;
        }

        try {
            return (bool) $this->engine->verifyKey($secret, $code, self::WINDOW);
        } catch (InvalidCharactersException|SecretKeyTooShortException) {
            return false;
        }
    }

    /**
     * Whether the submitted code is one already spent.
     *
     * The guard keeps a short *list* of digests rather than only the newest.
     * Remembering one value was not enough: it was overwritten by the next
     * successful sign-in, while the verifier still accepted the previous code
     * inside its +/-1-step tolerance. Measured against the running app — sign
     * in with code A, wait for the next step, sign in with code B, then
     * submit A again: A was accepted a second time.
     *
     * Both halves must hold for a hit: the digest must match an entry, *and*
     * that entry must still be inside the guard window. Matching on the value
     * rather than the clock alone is what keeps a simple mistype from being
     * reported as a replay, which would falsely imply the operator's phone
     * had been compromised.
     *
     * @param  array<int, array{h?: string, t?: int}>|null  $recentCodes
     */
    public function isReplayedCode(string $submittedCode, ?array $recentCodes): bool
    {
        if (empty($recentCodes)) {
            return false;
        }

        $digest = $this->hashCode($submittedCode);

        foreach ($recentCodes as $entry) {
            $hash = (string) ($entry['h'] ?? '');

            if ($hash === '' || ! hash_equals($hash, $digest)) {
                continue;
            }

            // Digest matches. Only a spend inside the guard window counts as
            // a replay; an older match is harmless because that code's time
            // step has already passed and verify() would reject it anyway.
            return $this->isWithinGuardWindow(
                (new DateTimeImmutable)->setTimestamp((int) ($entry['t'] ?? 0))
            );
        }

        return false;
    }

    /**
     * The digest list with $code recorded and expired entries dropped.
     *
     * Called on every successful TOTP sign-in. Entries leave the list once no
     * code from their time step can still verify, so the list is bounded by
     * construction (one per step across the guard window) and cannot grow
     * without limit no matter how often an administrator signs in.
     *
     * @param  array<int, array{h?: string, t?: int}>|null  $recentCodes
     * @return array<int, array{h: string, t: int}>
     */
    public function rememberSpentCode(?array $recentCodes, string $code, ?int $at = null): array
    {
        $at ??= time();
        $digest = $this->hashCode($code);
        $kept = [];

        foreach ($recentCodes ?? [] as $entry) {
            $hash = (string) ($entry['h'] ?? '');
            $spentAt = (int) ($entry['t'] ?? 0);

            // Drop anything whose step can no longer be verified, and the
            // entry for this very code, which is re-added below with a fresh
            // timestamp. Re-adding rather than skipping keeps the newest
            // spend of a repeated value authoritative.
            if ($hash === '' || $spentAt <= $at - self::REPLAY_GUARD_SECONDS) {
                continue;
            }

            if (hash_equals($hash, $digest)) {
                continue;
            }

            $kept[] = ['h' => $hash, 't' => $spentAt];
        }

        $kept[] = ['h' => $digest, 't' => $at];

        return $kept;
    }

    /** Digest recorded against an account when a code is spent. */
    public function hashCode(string $code): string
    {
        return hash('sha256', $code);
    }

    /**
     * True while a code spent at $lastUsedAt is still inside its time step.
     *
     * Retained for callers that only have a timestamp — chiefly the settings
     * screen, which shows how long the current step lasts.
     */
    public function isWithinGuardWindow(?DateTimeInterface $lastUsedAt): bool
    {
        return $lastUsedAt !== null
            && $lastUsedAt->getTimestamp() > time() - self::REPLAY_GUARD_SECONDS;
    }

    /**
     * Generate recovery codes, returning them in plaintext for one-time
     * display alongside their digests for storage.
     *
     * The plaintext is never persisted — only the SHA-256 digests go to the
     * database — so a leaked table dump cannot be replayed as a login.
     *
     * @return array{0: list<string>, 1: list<string>}  [plaintext, digests]
     */
    public function generateRecoveryCodes(int $count = 8): array
    {
        $plain = [];

        for ($i = 0; $i < $count; $i++) {
            $plain[] = $this->randomRecoveryCode();
        }

        return [$plain, array_map([$this, 'digestRecoveryCode'], $plain)];
    }

    /**
     * Check a submitted recovery code against the stored digests.
     *
     * Compares with hash_equals so the loop does not leak which digest
     * matched through timing.
     *
     * @param  list<string>  $digests
     */
    public function matchesRecoveryCode(string $code, array $digests): bool
    {
        $candidate = $this->digestRecoveryCode($code);

        foreach ($digests as $digest) {
            if (hash_equals((string) $digest, $candidate)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Normalise a recovery code for comparison: uppercase, and strip the
     * separators people add when transcribing from a printout.
     */
    public function normaliseRecoveryCode(string $code): string
    {
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code) ?? '');
    }

    public function digestRecoveryCode(string $code): string
    {
        return hash('sha256', $this->normaliseRecoveryCode($code));
    }

    /**
     * Draw a code from the unambiguous alphabet using a CSPRNG.
     *
     * `random_int` rather than shuffle()/rand(): recovery codes are the one
     * credential here that protects against permanent lockout, so a
     * predictable generator would undermine the whole factor.
     */
    private function randomRecoveryCode(): string
    {
        $alphabetLength = strlen(self::RECOVERY_ALPHABET);
        $code = '';

        for ($i = 0; $i < self::RECOVERY_LENGTH; $i++) {
            $code .= self::RECOVERY_ALPHABET[random_int(0, $alphabetLength - 1)];
        }

        // Grouped for legibility when written down or read aloud.
        return substr($code, 0, 5).'-'.substr($code, 5);
    }
}

  