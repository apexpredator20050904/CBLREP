<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a barter listing declare what its owner wants in return.
 *
 * Until now only the *proposer* could describe their side of a trade
 * (`exchanges.offered_item` / `offered_resource_id`). The owner had no way to
 * say "I'll trade my drill, but I want a hammer back" — so every proposal was
 * a guess the owner could only reject.
 *
 * It is advisory, not a constraint: the owner still accepts or rejects each
 * proposal, so an offer that does not match simply gets declined rather than
 * failing validation. That keeps the field useful without making it a
 * second state machine.
 *
 * Nullable and capped at 160 chars because it is optional metadata on an
 * existing row — free and paid listings have no return side at all, so the
 * column stays NULL for them.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('resources', 'wanted_item')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->string('wanted_item', 160)->nullable()->after('compensation_type');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('resources', 'wanted_item')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->dropColumn('wanted_item');
            });
        }
    }
};
