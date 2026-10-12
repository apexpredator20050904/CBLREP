<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Email-based two-factor authentication for the admin console.
 *
 * Two parts:
 *
 *  1. `users.two_factor_enabled` — per-administrator opt-in. Opt-in rather
 *     than always-on is deliberate: a mailed-code factor that is mandatory
 *     but misconfigured (no SMTP, wrong MAIL_FROM) would lock every
 *     administrator out of the portal with no recovery path.
 *
 *  2. `admin_two_factor_challenges` — a pending verification. The code is
 *     stored as a bcrypt hash, never in plaintext, so a leaked table dump or
 *     a read-only SQL-injection cannot be replayed against the login form.
 *     Each row is single-use (`consumed_at`), time-boxed (`expires_at`),
 *     attempt-capped (`attempts`) and bound to the browser that started the
 *     sign-in via `challenge_token`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('two_factor_enabled')->default(false)->after('account_status');
        });

        Schema::create('admin_two_factor_challenges', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->cascadeOnDelete();

            // bcrypt hash of the 6-digit code — never the code itself.
            $table->string('code_hash');

            // SHA-256 of a 64-char random token issued to the browser that
            // cleared stage 1. Binding verification to that token is what
            // stops an intercepted code from being redeemed by a third party.
            $table->string('challenge_token', 64)->unique();

            // Wrong codes allowed before the challenge is destroyed.
            $table->unsignedTinyInteger('attempts')->default(0);

            $table->timestamp('expires_at');
            $table->timestamp('consumed_at')->nullable();

            $table->string('ip_address', 45)->nullable();
            $table->string('user_agent')->nullable();

            $table->timestamps();

            // Serves the "latest unexpired challenge for this admin" lookup
            // and lets a scheduled prune skip rows that are already indexed.
            $table->index(['user_id', 'expires_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('admin_two_factor_challenges');

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('two_factor_enabled');
        });
    }
};