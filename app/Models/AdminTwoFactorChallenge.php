<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A pending second-factor step for one administrator sign-in.
 *
 * The class is the single place the security rules live — the controller
 * never touches a hash or an expiry itself. `isUsable()` gates every
 * redemption, and consumption is simply `delete()`, so a redeemed or burned
 * challenge leaves no row to replay. Because the checks are made against a
 * freshly-read row and the write is a delete, two concurrent requests for the
 * same code cannot both succeed.
 */
class AdminTwoFactorChallenge extends Model
{
    /** Minutes a stage-1 challenge stays valid. */
    public const TTL_MINUTES = 10;

    /** Wrong codes tolerated before the challenge is destroyed. */
    public const MAX_ATTEMPTS = 5;

    /**
     * Seconds before a new challenge may be issued for the same account.
     *
     * TOTP codes refresh on their own every 30 seconds, so there is no
     * resend step in the UI — this only stops someone holding stage-1
     * credentials from hammering the endpoint to reset the attempt budget
     * and buy a fresh set of guesses.
     *
     * The check is enforced against `users.two_factor_challenge_issued_at`,
     * NOT against this table: the lockout path deletes challenge rows, so a
     * cooldown that consults them is reset by burning a challenge.
     */
    public const CHALLENGE_COOLDOWN = 60;

    protected $fillable = [
        'user_id',
        'challenge_token',
        'expires_at',
        'ip_address',
        'user_agent',
    ];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'consumed_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isExpired(): bool
    {
        return Carbon::now()->gte($this->expires_at);
    }

    public function isConsumed(): bool
    {
        return $this->consumed_at !== null;
    }

    /** Usable = not redeemed, not timed out, and still has attempts left. */
    public function isUsable(): bool
    {
        return ! $this->isConsumed()
            && ! $this->isExpired()
            && $this->attempts < self::MAX_ATTEMPTS;
    }

    /**
     * True while the code is still redeemable but the owner has burned
     * through the attempt budget — the challenge is spent, but it is worth
     * telling the admin *why* rather than failing with a generic message.
     */
    public function isLockedOut(): bool
    {
        return ! $this->isConsumed() && $this->attempts >= self::MAX_ATTEMPTS;
    }

    public function secondsUntilExpiry(): int
    {
        return max(0, Carbon::now()->diffInSeconds($this->expires_at, false));
    }
}