<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Multi-photo listings.
 *
 * A single `image_path` cannot show a used item's condition — the whole point of
 * a community marketplace photo. This adds an ordered list of image paths while
 * leaving `image_path` as the cover (first) image, so existing consumers
 * (ExchangeController, AdminPortalController, the feed thumbnail) keep working
 * unchanged; only the listing payload grows an `image_urls` array.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (! Schema::hasColumn('resources', 'image_paths')) {
                $table->json('image_paths')->nullable()->after('image_path');
            }
        });
    }

    public function down(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (Schema::hasColumn('resources', 'image_paths')) {
                $table->dropColumn('image_paths');
            }
        });
    }
};
