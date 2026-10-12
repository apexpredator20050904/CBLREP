<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * AuditLog::record() deliberately passes a null actor for events that happen
 * before the request is authenticated (failed admin logins, rejected password
 * reset codes). The original table created admin_id as NOT NULL, so any such
 * audit write raised an SQL integrity error and turned a clean 401/422 into a
 * 500. This aligns the schema with the model's documented intent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('audit_logs', function (Blueprint $table) {
            $table->foreignId('admin_id')->nullable()->change();
        });
    }

    public function down(): void
    {
        // Rows with no actor cannot satisfy the old NOT NULL constraint.
        DB::table('audit_logs')->whereNull('admin_id')->delete();

        Schema::table('audit_logs', function (Blueprint $table) {
            $table->foreignId('admin_id')->nullable(false)->change();
        });
    }
};
