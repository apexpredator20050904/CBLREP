<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Narrows the exchange system to Direct Bartering only.
 *
 * The platform previously supported three models — freecycling (one-way
 * gifting), temporary lending (borrow + return) and bartering (item-for-item).
 * Only bartering remains, because it is the only model where both parties
 * receive something of value. Gifting created a one-sided transfer with no
 * consideration, and lending created a custody obligation with a return timer;
 * neither is a "transaction" in the accounting sense and both muddied the
 * project's research value.
 *
 * Changes
 *   + exchanges.offered_resource_id   the proposer's own listing, offered back
 *   + exchanges.offered_item          free-text alternative for skill trades
 *   - exchanges.scheduled_return_date lending return timer
 *   - exchanges.return_date           actual return date
 *   - resources.exchange_type         let a listing declare itself giftable
 *
 * `offered_*` is what makes a one-sided gifting row unrepresentable: a valid
 * barter must name what the proposer gives in return.
 */
return new class extends Migration
{
    public function up(): void
    {
        // Legacy rows that are not bartering cannot be represented once the
        // lending columns are gone — they had no "offered" side at all.
        DB::table('exchanges')
            ->where('exchange_type', '!=', 'barter')
            ->delete();

        if (Schema::hasColumn('exchanges', 'scheduled_return_date')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->dropColumn('scheduled_return_date');
            });
        }

        if (Schema::hasColumn('exchanges', 'return_date')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->dropColumn('return_date');
            });
        }

        Schema::table('exchanges', function (Blueprint $table) {
            // What the proposer puts up in return. `offered_item` covers
            // skill-for-skill trades that have no listing behind them.
            $table->foreignId('offered_resource_id')
                ->nullable()
                ->after('resource_id')
                ->constrained('resources')
                ->nullOnDelete();

            $table->string('offered_item')->nullable()->after('offered_resource_id');
        });

        // Dropping this column is what stops a listing from being published as
        // giftable/lendable; "is it an offer or a need" is all that remains.
        if (Schema::hasColumn('resources', 'exchange_type')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->dropColumn('exchange_type');
            });
        }

        DB::table('exchanges')->update(['exchange_type' => 'barter']);
    }

    public function down(): void
    {
        if (! Schema::hasColumn('resources', 'exchange_type')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->string('exchange_type')->nullable()->after('type');
            });
        }

        if (! Schema::hasColumn('exchanges', 'offered_item')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->dropForeign(['offered_resource_id']);
                $table->dropColumn(['offered_resource_id', 'offered_item']);
            });
        }

        if (! Schema::hasColumn('exchanges', 'scheduled_return_date')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->date('scheduled_return_date')->nullable()->after('status');
                $table->date('return_date')->nullable()->after('scheduled_return_date');
            });
        }

        // Structural rollback only. Barter rows keep their `offered_*` data,
        // which has no equivalent in the freecycling/lending schema and is
        // therefore not reverted by this migration.
    }
};
