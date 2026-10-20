<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Lets a NEED say how much it needs ("5 kg of rice", "2 sacks of charcoal").
 *
 * An Offer is one thing a member already owns, so it has no quantity. A Need
 * is a shopping list entry: the same real-world want ad that says "looking for
 * rice" almost always says how much — and a neighbour answering "I have rice"
 * needs to know whether that means half a kilo or five.
 *
 * Free-text on purpose (not an integer): "2 sacks", "half a kilo" and "a
 * bundle of firewood" are all legitimate answers, and a numeric column would
 * force the member to invent a unit the portal does not understand.
 *
 * Nullable and cleared for Offers, so the field is only ever populated on the
 * listing direction where it means something.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('resources', 'quantity')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->string('quantity', 60)->nullable()->after('condition');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('resources', 'quantity')) {
            Schema::table('resources', function (Blueprint $table) {
                $table->dropColumn('quantity');
            });
        }
    }
};
