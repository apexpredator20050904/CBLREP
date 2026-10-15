<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Move the challenge-issuance cooldown onto the account row.
 *
 * The cooldown added in 000003 was checked by looking for a recent row in
 * `admin_two_factor_challenges`. That check is trivially defeated, because
 * the lockout path *deletes* the challenge row it is looking for:
 *
 *   1. attacker holds valid stage-1 credentials
 *   2. POST /admin-login  -> challenge issued, 5 attempts available
 *   3. submit 5 wrong codes -> challenge destroyed, row gone
 *   4. POST /admin-login  -> the "recent challenge" check finds nothing,
 *                            so a brand-new 5-attempt budget is issued
 *   5. repeat — the 1,000,000-code space becomes reachable over hours
 *
 * Measured against the running app: three full rounds (15 guesses) completed
 * in seconds, each round issuing a fresh challenge despite a 60-second window.
 *
 * `two_factor_challenge_issued_at` lives on `users`, so no amount of challenge
 * cleanup can reset it. TOTP refreshes its own code every 30 seconds and there
 * is no resend button, so this timestamp throttles *issuance* only and never
 * interferes with an administrator who is simply mistyping.
 *
 * Nullable: every existing account has never issued a challenge, which must
 * read as "not in cooldown" rather than as an epoch comparison.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('two_factor_challenge_issued_at')
                ->nullable()
                ->after('two_factor_last_code_hash')
                ->comment('When a stage-1 2FA challenge was last minted for this account.');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('two_factor_challenge_issued_at');
        });
    }
};
