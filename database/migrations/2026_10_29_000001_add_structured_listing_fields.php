<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Structured quantity and urgency for NEED listings.
 *
 * The original `quantity` column is free text on purpose ("2 sacks", "half a
 * kilo"), but it forces every client to parse the member's sentence before it
 * can display, sort or filter the amount. This migration adds the machine
 * readable half:
 *
 *   quantity_value — the number ("5")
 *   quantity_unit  — the unit key ("kg", "sack", "hour")
 *   urgency        — how soon a NEED has to be met
 *
 * `quantity` is deliberately kept and still written (composed from the pair)
 * so older APK builds and the admin console keep rendering, and so existing
 * free-text rows are never destroyed. Offers ignore all three columns — the
 * controller normalises them to NULL for that direction.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (! Schema::hasColumn('resources', 'quantity_value')) {
                $table->decimal('quantity_value', 10, 2)->nullable()->after('quantity');
            }
            if (! Schema::hasColumn('resources', 'quantity_unit')) {
                $table->string('quantity_unit', 16)->nullable()->after('quantity_value');
            }
            if (! Schema::hasColumn('resources', 'urgency')) {
                $table->string('urgency', 16)->nullable()->after('quantity_unit');
            }
        });
    }

    public function down(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            foreach (['urgency', 'quantity_unit', 'quantity_value'] as $column) {
                if (Schema::hasColumn('resources', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
