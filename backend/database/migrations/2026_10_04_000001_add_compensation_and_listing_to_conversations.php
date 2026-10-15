<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Flexible Compensation & Direct Inquiry.
 *
 * CBLREP supports three community-sharing modes on every listing:
 *
 *   free   — a gift to a neighbour (no price)
 *   barter — an item/skill swap (no price)
 *   paid   — a priced sale (price required)
 *
 * and links each inquiry conversation to the listing it started from, so a
 * member or moderator can always see *which* post a chat is about.
 *
 * Barangay + purok/sitio already live on `resources` (added by
 * 2026_10_03_000003_add_structured_location_fields) and are left intact —
 * every listing keeps its hyper-local context.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            // 'free' | 'barter' | 'paid' — defaults to barter, the portal's
            // historical single mode, so existing rows stay meaningful.
            if (! Schema::hasColumn('resources', 'compensation_type')) {
                $table->string('compensation_type', 16)
                    ->default('barter')
                    ->after('type')
                    ->index();
            }
            // Only meaningful for `paid`; null for free/barter.
            if (! Schema::hasColumn('resources', 'price')) {
                $table->decimal('price', 10, 2)->nullable()->after('compensation_type');
            }
        });

        // A paid listing must carry a price; free/barter must not. Clearing
        // stray legacies first keeps the check constraint satisfiable on any
        // pre-existing row.
        DB::table('resources')
            ->where('compensation_type', 'paid')
            ->whereNull('price')
            ->update(['compensation_type' => 'barter', 'price' => null]);

        DB::table('resources')->where('compensation_type', '!=', 'paid')->update(['price' => null]);

        // Conversations become listing-scoped. `buyer_id` is the member who
        // opened the inquiry, `seller_id` the listing owner; participants keep
        // working for the existing non-listing (person-to-person) threads.
        Schema::table('conversations', function (Blueprint $table) {
            if (! Schema::hasColumn('conversations', 'listing_id')) {
                $table->foreignId('listing_id')
                    ->nullable()
                    ->after('id')
                    ->constrained('resources')
                    ->nullOnDelete();
                $table->index(['listing_id', 'updated_at']);
            }
            if (! Schema::hasColumn('conversations', 'buyer_id')) {
                $table->foreignId('buyer_id')
                    ->nullable()
                    ->after('listing_id')
                    ->constrained('users')
                    ->nullOnDelete();
            }
            if (! Schema::hasColumn('conversations', 'seller_id')) {
                $table->foreignId('seller_id')
                    ->nullable()
                    ->after('buyer_id')
                    ->constrained('users')
                    ->nullOnDelete();
            }
        });

        // The original unique(participant_one_id, participant_two_id) allowed
        // exactly one thread per pair. Direct inquiries need one thread *per
        // listing*, so the pair may legitimately repeat. MySQL keeps the
        // participant foreign keys leaning on that unique index, so they are
        // dropped, the index swapped for a plain lookup index, then re-added.
        $uniqueName = 'conversations_participant_one_id_participant_two_id_unique';
        $plainName = 'conversations_participants_index';

        if ($this->hasIndex('conversations', $uniqueName)) {
            Schema::table('conversations', function (Blueprint $table) {
                $table->dropForeign(['participant_one_id']);
                $table->dropForeign(['participant_two_id']);
            });
            Schema::table('conversations', function (Blueprint $table) {
                $table->dropUnique(['participant_one_id', 'participant_two_id']);
            });
            Schema::table('conversations', function (Blueprint $table) use ($plainName) {
                $table->index(['participant_one_id', 'participant_two_id'], $plainName);
            });
            Schema::table('conversations', function (Blueprint $table) {
                $table->foreign('participant_one_id')->references('id')->on('users')->cascadeOnDelete();
                $table->foreign('participant_two_id')->references('id')->on('users')->cascadeOnDelete();
            });
        } elseif (! $this->hasIndex('conversations', $plainName)) {
            Schema::table('conversations', function (Blueprint $table) use ($plainName) {
                $table->index(['participant_one_id', 'participant_two_id'], $plainName);
            });
        }
    }

    /** True when `$table` has an index/constraint named `$index`. */
    private function hasIndex(string $table, string $index): bool
    {
        foreach (\Illuminate\Support\Facades\DB::select("SHOW INDEX FROM `{$table}`") as $row) {
            if ($row->Key_name === $index) {
                return true;
            }
        }

        return false;
    }

    public function down(): void
    {
        // Restore the original one-thread-per-pair constraint. Any duplicate
        // listing threads created since would block it, so collapse them first
        // by detaching their listing scope (rows are kept, not deleted).
        \Illuminate\Support\Facades\DB::table('conversations')
            ->whereNotNull('listing_id')
            ->update(['listing_id' => null, 'buyer_id' => null, 'seller_id' => null]);

        $uniqueName = 'conversations_participant_one_id_participant_two_id_unique';
        $plainName = 'conversations_participants_index';

        if ($this->hasIndex('conversations', $plainName) && ! $this->hasIndex('conversations', $uniqueName)) {
            Schema::table('conversations', function (Blueprint $table) {
                $table->dropForeign(['participant_one_id']);
                $table->dropForeign(['participant_two_id']);
            });
            Schema::table('conversations', function (Blueprint $table) use ($plainName) {
                $table->dropIndex($plainName);
            });
            Schema::table('conversations', function (Blueprint $table) {
                $table->unique(['participant_one_id', 'participant_two_id']);
            });
            Schema::table('conversations', function (Blueprint $table) {
                $table->foreign('participant_one_id')->references('id')->on('users')->cascadeOnDelete();
                $table->foreign('participant_two_id')->references('id')->on('users')->cascadeOnDelete();
            });
        }

        Schema::table('conversations', function (Blueprint $table) {
            foreach (['seller_id', 'buyer_id'] as $column) {
                if (Schema::hasColumn('conversations', $column)) {
                    $table->dropForeign([$column]);
                    $table->dropColumn($column);
                }
            }
            if (Schema::hasColumn('conversations', 'listing_id')) {
                $table->dropForeign(['listing_id']);
                $table->dropIndex(['listing_id', 'updated_at']);
                $table->dropColumn('listing_id');
            }
        });

        Schema::table('resources', function (Blueprint $table) {
            foreach (['price', 'compensation_type'] as $column) {
                if (Schema::hasColumn('resources', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
