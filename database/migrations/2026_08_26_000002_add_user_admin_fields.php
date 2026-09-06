<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'verification_status')) {
                $table->string('verification_status')->default('pending')->after('is_verified');
            }
            if (! Schema::hasColumn('users', 'account_status')) {
                $table->string('account_status')->default('active')->after('verification_status');
            }
            if (! Schema::hasColumn('users', 'admin_note')) {
                $table->text('admin_note')->nullable()->after('account_status');
            }
        });

        // Backfill existing verified members so status never disagrees with is_verified.
        DB::table('users')
            ->where('is_verified', true)
            ->where('verification_status', 'pending')
            ->update(['verification_status' => 'verified']);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            foreach (['admin_note', 'account_status', 'verification_status'] as $column) {
                if (Schema::hasColumn('users', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
