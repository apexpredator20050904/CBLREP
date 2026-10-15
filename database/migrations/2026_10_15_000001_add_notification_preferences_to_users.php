<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Per-member push-notification preferences.
 *
 * Until now the mobile Settings toggles lived only in the device's
 * SharedPreferences, so the server — the only party that can actually send an
 * FCM push — had no idea a member had muted barter alerts. Storing the choices
 * here lets the NotificationService honour them. Null means "never configured":
 * every category is treated as on, so existing members keep receiving pushes.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'notification_preferences')) {
                $table->json('notification_preferences')->nullable()->after('purok_sitio');
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'notification_preferences')) {
                $table->dropColumn('notification_preferences');
            }
        });
    }
};
