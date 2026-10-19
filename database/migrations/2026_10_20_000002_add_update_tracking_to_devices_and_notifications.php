<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Update-notification bookkeeping.
 *
 * Two small additions that together let the portal tell members a new app
 * build is out:
 *
 *   device_tokens.build_number          the versionCode the device is running.
 *                                       The server uses it to notify only the
 *                                       members who are actually behind,
 *                                       instead of buzzing everybody.
 *
 *   member_notifications.app_version_code
 *                                       the release an "a new version is
 *                                       available" row refers to. It is the
 *                                       dedup key, so re-running the
 *                                       announcement for the same release
 *                                       never notifies the same member twice.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('device_tokens', function (Blueprint $table) {
            if (! Schema::hasColumn('device_tokens', 'build_number')) {
                $table->unsignedInteger('build_number')->nullable()->after('platform');
            }
        });

        Schema::table('member_notifications', function (Blueprint $table) {
            if (! Schema::hasColumn('member_notifications', 'app_version_code')) {
                $table->unsignedInteger('app_version_code')->nullable()->after('type');
                $table->index(['user_id', 'app_version_code']);
            }
        });
    }

    public function down(): void
    {
        Schema::table('member_notifications', function (Blueprint $table) {
            if (Schema::hasColumn('member_notifications', 'app_version_code')) {
                $table->dropIndex(['user_id', 'app_version_code']);
                $table->dropColumn('app_version_code');
            }
        });

        Schema::table('device_tokens', function (Blueprint $table) {
            if (Schema::hasColumn('device_tokens', 'build_number')) {
                $table->dropColumn('build_number');
            }
        });
    }
};
