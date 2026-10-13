<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Dual-Confirmation Model for barter completion (CBLREP capstone).
 *
 * An accepted barter may only reach `completed` when BOTH parties confirm
 * the handover independently on the mobile app:
 *
 *   proposer (receiver_id) → proposer_confirmed (+ proposer_confirmed_at)
 *   owner    (provider_id) → owner_confirmed   (+ owner_confirmed_at)
 *
 * Single-party `PATCH /api/exchanges/{id} {status: completed}` is retired by
 * this change — completion now flows exclusively through
 * POST /api/exchanges/{id}/confirm-completion, which flips only the caller's
 * flag and promotes the row to `completed` once both flags are true.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('exchanges', function (Blueprint $table) {
            $table->boolean('proposer_confirmed')->default(false)->after('status');
            $table->boolean('owner_confirmed')->default(false)->after('proposer_confirmed');
            $table->timestamp('proposer_confirmed_at')->nullable()->after('owner_confirmed');
            $table->timestamp('owner_confirmed_at')->nullable()->after('proposer_confirmed_at');
        });
    }

    public function down(): void
    {
        Schema::table('exchanges', function (Blueprint $table) {
            $table->dropColumn([
                'proposer_confirmed',
                'owner_confirmed',
                'proposer_confirmed_at',
                'owner_confirmed_at',
            ]);
        });
    }
};
