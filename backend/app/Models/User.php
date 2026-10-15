<?php

namespace App\Models;

use App\Models\Concerns\CanonicalizesPurokSitio;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use CanonicalizesPurokSitio, HasApiTokens, Notifiable;

    public const ROLE_USER = 'user';
    public const ROLE_ADMIN = 'admin';
    public const ROLE_SUPER_ADMIN = 'super_admin';

    /** All assignable roles (least → most privilege). */
    public const ROLES = [
        self::ROLE_USER,
        self::ROLE_ADMIN,
        self::ROLE_SUPER_ADMIN,
    ];

        protected $fillable = [
        'name',
        // Relative path on the public disk (avatars/…). Handled by the
        // avatar endpoints, never set from a bulk profile payload.
        'avatar_path',
        'email',
        'password',
        'role',
        'is_verified',
        'barangay_or_location',
        'student_status',
        'student_school',
        'verification_document_path',
        'verification_document_type',
        'verification_submitted_at',
        'verification_note',
        // Needed so AuthController::submitVerification() and the admin
        // approve/reject paths can flip the review lifecycle. Without this,
        // submissions persisted the proof but the status silently stayed
        // 'unverified', hiding them from the admin queue.
        'verification_status',
        // Structured location: one of the 20 official Trinidad barangays
        // (App\Support\Barangays) plus the specific purok/sitio.
        'barangay',
        'purok_sitio',
        // NOTE: two_factor_enabled is intentionally NOT fillable.
        // Leaving it out means it can never arrive from a register/profile/
        // admin-update request body, so no request can silently turn a
        // second factor off. Toggle it through enableTwoFactor() below,
        // which only the 2FA settings endpoints and artisan tinker call.
    ];

    protected $hidden = [
        'password',
        'remember_token',
        // Never serialised. `two_factor_secret` is the shared TOTP seed:
        // leaking it to any client that reads a user resource would let that
        // client generate valid codes forever. The encrypted cast keeps it
        // off disk as plaintext; $hidden keeps it out of every response.
        'two_factor_secret',
        'two_factor_recovery_codes',
        // Spent-code digests exist only to block replays. They are keyed
        // hashes with no client-side consumer, so they stay out of payloads.
        'two_factor_recent_codes',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_verified' => 'boolean',
            'student_status' => 'boolean',
            'verification_submitted_at' => 'datetime',
            // Must be cast: a raw 0/1 from MySQL is falsy-falsy in PHP, and
            // `if ($user->two_factor_enabled)` on the integer 0 works by luck
            // while the string '0' from some drivers would be truthy.
            'two_factor_enabled' => 'boolean',
            'two_factor_confirmed_at' => 'datetime',
            'two_factor_last_used_at' => 'datetime',
            'two_factor_challenge_issued_at' => 'datetime',
            // Replay guard: the digests of recently spent codes. Plain `array`
            // and not `encrypted:array` on purpose — every entry is a SHA-256
            // digest of a value that has already been consumed and will never
            // verify again, so there is nothing here worth decrypting. The
            // secret and the recovery list *are* encrypted because both can
            // still mint live codes.
            'two_factor_recent_codes' => 'array',
            // Authenticated at rest. The secret is 16 base32 chars and the
            // recovery list is 8 digests, but both are exactly the material
            // an attacker needs to mint valid 6-digit codes, so neither is
            // stored in the clear. Requires a valid APP_KEY to decrypt - if
            // it is ever rotated, every enrolled admin must re-enrol.
            'two_factor_secret' => 'encrypted',
            'two_factor_recovery_codes' => 'encrypted:array',
            'notification_preferences' => 'array',
        ];
    }

    // ------------------------------------------------------------------
    // Push-notification preferences
    // ------------------------------------------------------------------

    /** The categories a member can tune independently in Settings. */
    public const NOTIFICATION_CATEGORIES = ['messages', 'exchanges', 'announcements', 'account'];

    /**
     * The member's effective preferences, with every category defaulting on.
     *
     * `notification_preferences` is null until the member ever touches a
     * toggle, so a missing key must read as "enabled" rather than "off".
     *
     * @return array{enabled: bool, messages: bool, exchanges: bool, announcements: bool, account: bool}
     */
    public function notificationPreferences(): array
    {
        $stored = is_array($this->notification_preferences) ? $this->notification_preferences : [];

        $effective = ['enabled' => true];
        foreach (self::NOTIFICATION_CATEGORIES as $category) {
            $effective[$category] = true;
        }

        foreach ($effective as $key => $default) {
            if (array_key_exists($key, $stored)) {
                $effective[$key] = (bool) $stored[$key];
            }
        }

        return $effective;
    }

    /**
     * Whether an FCM push for the given category may be sent to this member.
     *
     * The master `enabled` switch wins: turning push off silences every
     * category regardless of the individual toggles. The in-app inbox row is
     * always recorded by NotificationService — this only gates the push.
     */
    public function wantsPush(string $category): bool
    {
        $prefs = $this->notificationPreferences();

        if ($prefs['enabled'] === false) {
            return false;
        }

        return ($prefs[$category] ?? true) !== false;
    }

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function resources()
    {
        return $this->hasMany(Resource::class);
    }

    public function conversationsAsFirst()
    {
        return $this->hasMany(Conversation::class, 'participant_one_id');
    }

    public function conversationsAsSecond()
    {
        return $this->hasMany(Conversation::class, 'participant_two_id');
    }

    public function notifications()
    {
        return $this->hasMany(MemberNotification::class);
    }

    public function deviceTokens()
    {
        return $this->hasMany(DeviceToken::class);
    }

    // ------------------------------------------------------------------
    // Helpers used by the admin controllers
    // ------------------------------------------------------------------

    public function isAdmin(): bool
    {
        return in_array($this->role, [self::ROLE_ADMIN, self::ROLE_SUPER_ADMIN], true);
    }

    /**
     * Turn the authenticator-app second factor on or off.
     *
     * Not settable through $fillable — see the note in the fillable array.
     * Enabling invalidates any outstanding challenge so a code minted under
     * the old setting cannot be redeemed afterwards.
     *
     * $recoveryDigests is required when enabling: a factor that cannot be
     * recovered is a factor that can permanently lock the last administrator
     * out of the portal. It is required rather than defaulted so no caller
     * can forget it.
     *
     * @param  list<string>  $recoveryDigests
     */
    public function enableTwoFactor(array $recoveryDigests): void
    {
        $this->two_factor_enabled = true;
        $this->two_factor_confirmed_at = now();
        $this->two_factor_recovery_codes = $recoveryDigests;

        AdminTwoFactorChallenge::where('user_id', $this->id)->delete();

        $this->save();
    }

    /**
     * Disable the factor and destroy the enrolled secret.
     *
     * Clearing the secret rather than leaving it dormant matters: a dormant
     * secret is still a valid TOTP seed, and leaving it on the row means any
     * future bug that re-reads `two_factor_enabled` differently re-opens a
     * door that was deliberately closed.
     */
    public function disableTwoFactor(): void
    {
        $this->two_factor_enabled = false;
        $this->two_factor_secret = null;
        $this->two_factor_confirmed_at = null;
        $this->two_factor_recovery_codes = null;
        $this->two_factor_last_used_at = null;
        // The replay ledger protects a factor that no longer exists once 2FA
        // is off, and a stale entry could shadow a digest issued during the
        // next enrolment. Cleared here as well as in issueToken().
        $this->two_factor_recent_codes = null;

        AdminTwoFactorChallenge::where('user_id', $this->id)->delete();

        $this->save();
    }

    /**
     * Whether a TOTP code is currently acceptable for this account.
     *
     * Checks enrolment integrity, not just the flag. A row where the flag is
     * set but the secret is missing or unconfirmed is a half-finished
     * enrolment; treating it as "2FA on" would lock the admin out with no
     * way back in through the UI.
     */
    public function hasEnrolledTwoFactor(): bool
    {
        return $this->two_factor_enabled
            && filled($this->two_factor_secret)
            && $this->two_factor_confirmed_at !== null;
    }

    /**
     * Seconds until this account may be issued another 2FA challenge.
     *
     * Stored on the account row rather than derived from
     * `admin_two_factor_challenges`, because the lockout path *deletes* the
     * challenge row. A cooldown that consults that table is therefore reset
     * by simply burning a challenge and asking for another: measured against
     * the running app, three full rounds of five guesses each completed in
     * seconds while the 60-second window was supposedly in force.
     *
     * Nothing deletes a `users` row during sign-in, so this cannot be reset
     * from outside.
     *
     * Returns 0 when a new challenge is permitted. Computed from integer
     * timestamps rather than `diffInSeconds`, whose sign convention changed
     * in Carbon 3 — a negative "wait" leaking into the error message would
     * be worse than no message at all.
     */
    public function challengeCooldownRemaining(): int
    {
        $issuedAt = $this->two_factor_challenge_issued_at;

        if ($issuedAt === null) {
            return 0;
        }

        $elapsed = now()->getTimestamp() - $issuedAt->getTimestamp();

        return max(0, AdminTwoFactorChallenge::CHALLENGE_COOLDOWN - $elapsed);
    }

    public function isSuperAdmin(): bool
    {
        return $this->role === self::ROLE_SUPER_ADMIN;
    }

    /**
     * The stored recovery-code digests — never throws.
     *
     * `two_factor_recovery_codes` is an `encrypted:array` column, so a value
     * written by a cast-bypassing path (a raw query-builder update, a manual
     * DB edit, an import) fails to decrypt and raises a DecryptException the
     * moment it is read. Reading it directly turned that into a 500 that
     * locked the administrator out of the whole console — including admins
     * who signed in with a perfectly valid TOTP code and never intended to
     * use recovery at all.
     *
     * Returning [] degrades gracefully. The only consequence is that no
     * recovery code can be redeemed, which is the correct outcome for an
     * unreadable column; the codes are re-issued from Settings → Two-Factor.
     */
    public function recoveryCodeDigests(): array
    {
        try {
            $codes = $this->two_factor_recovery_codes;
        } catch (\Throwable) {
            return [];
        }

        return is_array($codes) ? $codes : [];
    }

    /** Advisory count for the sign-in and Settings responses. */
    public function recoveryCodeCount(): int
    {
        return count($this->recoveryCodeDigests());
    }

    /** Human-readable role label used across the admin console. */
    public function roleLabel(): string
    {
        return match ($this->role) {
            self::ROLE_SUPER_ADMIN => 'Super Administrator',
            self::ROLE_ADMIN => 'System Administrator',
            default => 'General Member',
        };
    }

    /**
     * Resident verification lifecycle: unverified → pending → verified | rejected.
     * Anything unrecognised (including the pre-migration `pending` default with
     * no submitted document) reads back as `Unverified`, never as verified.
     */
    public function verificationStatusLabel(): string
    {
        return match ($this->verification_status) {
            'verified' => 'Verified',
            'pending' => 'Pending',
            'rejected' => 'Rejected',
            default => 'Unverified',
        };
    }

    public function accountStatusLabel(): string
    {
        return match ($this->account_status) {
            'suspended' => 'Suspended',
            default => 'Active',
        };
    }

    // ------------------------------------------------------------------
    // Profile photo
    // ------------------------------------------------------------------

    /**
     * Absolute URL for the member's profile photo, or null when they have none.
     *
     * Mirrors Resource::toFrontendListing()'s image handling: the stored value
     * is a relative path and the client rewrites the origin to whichever API
     * base actually won (LAN, emulator alias, or the shipped host).
     */
    public function avatarUrl(): ?string
    {
        return filled($this->avatar_path) ? asset('storage/'.$this->avatar_path) : null;
    }

    /**
     * Shape consumed by the admin users pages.
     */
        public function toFrontendArray(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'fullName' => $this->name,
            'avatar_url' => $this->avatarUrl(),
            'email' => $this->email,
            'role' => $this->roleLabel(),
            'raw_role' => $this->role,
            'is_super_admin' => $this->isSuperAdmin(),
            'is_verified' => (bool) $this->is_verified,
            'verification_status' => $this->verificationStatusLabel(),
            'verification_document_type' => $this->verification_document_type,
            'verification_note' => $this->verification_note,
            'verification_submitted_at' => $this->verification_submitted_at?->toISOString(),
            'account_status' => $this->accountStatusLabel(),
            'barangay_or_location' => $this->barangay_or_location,
            'barangay' => $this->barangay,
            'purok_sitio' => $this->purok_sitio,
            'is_student' => (bool) $this->student_status,
            'student_school' => $this->student_school,
            'resources_count' => $this->resources_count ?? $this->resources()->count(),
            'date_registered' => $this->created_at?->format('M j, Y'),
            'created_at' => $this->created_at?->format('M j, Y'),
        ];
    }
}
