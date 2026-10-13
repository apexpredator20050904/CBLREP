<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * RBAC + filtering support for the admin console.
 *
 * The `users.role` column is a plain string (user | admin), so adding the
 * "super_admin" tier needs no schema change — only lookup indexes so the
 * role/status/verification filters and DataTable queries stay fast once
 * the Trinidad directory grows.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! $this->indexExists('users', 'users_role_index')) {
                $table->index('role');
            }
            if (! $this->indexExists('users', 'users_account_status_index')) {
                $table->index('account_status');
            }
            if (! $this->indexExists('users', 'users_verification_status_index')) {
                $table->index('verification_status');
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            foreach (['users_role_index', 'users_account_status_index', 'users_verification_status_index'] as $index) {
                if ($this->indexExists('users', $index)) {
                    $table->dropIndex($index);
                }
            }
        });
    }

    private function indexExists(string $table, string $index): bool
    {
        return collect(Schema::getIndexes($table))->pluck('name')->contains($index);
    }
};
