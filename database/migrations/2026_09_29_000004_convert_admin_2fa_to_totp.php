<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Convert administrator 2FA from e-mailed OTP to authenticator-app TOTP.
 *
 * The preceding migration (…000003) built the challenge table around a
 * bcrypt-hashed code that was mailed out. TOTP inverts that: the code is
 * *derived* from a long-lived shared secret plus the current 30-second time
 * step, so there is nothing to store per sign-in — only the secret itself.
 * `code_hash` therefore becomes dead weight and is dropped.
 *
 * The challenge table is deliberately KEPT and repurposed rather than deleted.
 * TOTP codes are worth only ~20 bits of entropy and are valid for a whole
 * time step, so the rows that remain earn their place:
 *
 *   - challenge_token binds verification to the browser that passed stage 1,
 *     so an observed code cannot be redeemed from another device;
 *   - attempts caps guessing at 5 per issued token, which is the real
 *     brute-force control — far tighter than the 1,000,000-value keyspace;
 *   - ip_address/user_agent give the audit trail the context to detect a
 *     code being replayed from a different host than the one that started it.
 *
 * Enrolment state is split in two on purpose: `two_factor_secret` is written
 * the moment an admin opens the setup screen, but `two_factor_enabled` only
 * flips once they prove they can generate a code from it. A half-finished
 * enrolment can therefore never lock anyone out of the portal.
 *
 * `two_factor_secret` and `two_factor_recovery_codes` are `text`, not
 * `string`: they carry Laravel's `encrypted` cast, which wraps the value in
 * base64 JSON with an IV and a MAC, comfortably exceeding 255 bytes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Base32 shared secret. Written at setup, trusted only after
            // confirm. Read through the model's `encrypted` cast so it is
            // never at rest as plaintext in a table dump.
            $table->text('two_factor_secret')->nullable()->after('two_factor_enabled');

            // Proof that the secret was actually scanned. NULL means "a
            // setup was started but never finished".
            $table->timestamp('two_factor_confirmed_at')->nullable()->after('two_factor_secret');

            // SHA-256 digests of the one-time recovery codes, JSON-encoded.
            // Digests rather than bcrypt on purpose: these carry ~50 bits of
            // entropy, so a fast digest is cryptographically sufficient, and
            // eight sequential bcrypt comparisons would add ~500ms to every
            // login that falls back to a recovery code.
            $table->text('two_factor_recovery_codes')->nullable()->after('two_factor_confirmed_at');

            // When the last code was accepted. Lets us reject a replay of the
            // same 6-digit value inside its still-valid time step — the one
            // property a pure TOTP check does not give you for free.
            $table->timestamp('two_factor_last_used_at')->nullable()->after('two_factor_recovery_codes');
        });

        Schema::table('admin_two_factor_challenges', function (Blueprint $table) {
            $table->dropColumn('code_hash');
        });
    }

    public function down(): void
    {
        Schema::table('admin_two_factor_challenges', function (Blueprint $table) {
            // Restored as nullable: TOTP writes no code, so a row replayed
            // from a TOTP-era backup has nothing to put in it.
            $table->string('code_hash')->nullable();
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'two_factor_secret',
                'two_factor_confirmed_at',
                'two_factor_recovery_codes',
                'two_factor_last_used_at',
            ]);
        });
    }
};
