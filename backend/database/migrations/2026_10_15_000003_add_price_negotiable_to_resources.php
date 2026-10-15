<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Negotiable pricing for paid listings.
 *
 * CBLREP is barter-first, but a paid listing may still be open to a
 * counter-offer. This flag lets an owner advertise "price negotiable" and lets
 * a buyer send a structured offer into the listing's chat thread — the
 * Facebook-Marketplace pattern, and the only one that fits: the Exchange model
 * is deliberately a two-sided barter (see App\Models\Exchange), so a monetary
 * offer is a conversation, not a recorded exchange.
 *
 * Free and barter listings never carry it (there is no price to negotiate), so
 * the column is normalised to false whenever the compensation is not PAID.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (! Schema::hasColumn('resources', 'price_negotiable')) {
                $table->boolean('price_negotiable')->default(false)->after('price');
            }
        });
    }

    public function down(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (Schema::hasColumn('resources', 'price_negotiable')) {
                $table->dropColumn('price_negotiable');
            }
        });
    }
};
