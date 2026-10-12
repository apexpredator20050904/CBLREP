<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Record *which* code was last spent, not merely when.
 *
 * The replay guard added in 000004 compared only `two_factor_last_used_at`
 * against a 90-second window. That is too coarse: it refused *every* code
 * submitted shortly after a successful sign-in, so an administrator who
 * mistyped their next code was told "That code was already used" — a false
 * accusation that sent them looking for a stolen phone rather than at their
 * keyboard.
 *
 * Storing a SHA-256 of the consumed code lets the guard answer the question it
 * was always meant to answer — "is this the same code again?" — and nothing
 * else. A genuine typo now falls through to the normal verification path and
 * reports "invalid code", while an exact replay is still refused.
 *
 * The hash is unsalted, which is correct here: the input space is six decimal
 * digits, and unlike a password there is no dictionary to protect against. It
 * guards against replay, not disclosure, and the secret it derives from is
 * never stored alongside it in a way that would let the pair be reversed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('two_factor_last_code_hash', 64)
                ->nullable()
                ->after('two_factor_last_used_at')
                ->comment('SHA-256 of the last TOTP code spent at this account.');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('two_factor_last_code_hash');
        });
    }
};
