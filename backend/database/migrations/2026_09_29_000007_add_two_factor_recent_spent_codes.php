<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Replace the single remembered code digest with a short list of them.
 *
 * `two_factor_last_code_hash` held one value, so a spent code became
 * replayable the moment a newer one was used — the newer digest overwrote it,
 * while `TotpService::verify()` still accepted the older code inside its
 * +/-1-step tolerance. Measured against the running app: sign in with code A,
 * wait for the next step, sign in with code B, then submit A again — A was
 * accepted a second time.
 *
 * The column is dropped rather than kept alongside the new one, so there is
 * exactly one source of truth for the replay guard.
 */
return new class extends Migration
{
    /**
     * Entries are kept well beyond the window in which a TOTP code is still
     * verifiable, so no code can outlive its own guard entry.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->json('two_factor_recent_codes')->nullable()->after('two_factor_last_used_at');
        });

        // Carry the one remembered digest forward, otherwise an admin who is
        // mid-step at deploy time loses the protection they already had.
        foreach (DB::table('users')->whereNotNull('two_factor_last_code_hash')->get() as $user) {
            $spentAt = $user->two_factor_last_used_at !== null
                ? (int) strtotime((string) $user->two_factor_last_used_at)
                : time();

            DB::table('users')->where('id', $user->id)->update([
                'two_factor_recent_codes' => json_encode([
                    ['h' => (string) $user->two_factor_last_code_hash, 't' => $spentAt],
                ]),
            ]);
        }

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('two_factor_last_code_hash');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('two_factor_last_code_hash', 64)->nullable()->after('two_factor_last_used_at');
        });

        // Collapse back to the newest digest, matching the old column's
        // semantics as closely as a lossy direction allows.
        foreach (DB::table('users')->whereNotNull('two_factor_recent_codes')->get() as $user) {
            $list = json_decode((string) $user->two_factor_recent_codes, true);

            if (! is_array($list) || $list === []) {
                continue;
            }

            usort($list, fn ($a, $b) => ((int) ($b['t'] ?? 0)) <=> ((int) ($a['t'] ?? 0)));

            DB::table('users')->where('id', $user->id)->update([
                'two_factor_last_code_hash' => $list[0]['h'] ?? null,
            ]);
        }

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('two_factor_recent_codes');
        });
    }
};
