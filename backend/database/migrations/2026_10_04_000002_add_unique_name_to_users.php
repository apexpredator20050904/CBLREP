<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Enforce identity-name uniqueness at the database layer.
 *
 * Registration already rejects a duplicate full name (case- and
 * whitespace-insensitive) in AuthController, but a unique index makes the rule
 * hold under concurrency and direct DB writes too.
 *
 * Implementation note: this MariaDB build rejects functional-key indexes
 * (`UNIQUE ((LOWER(name)))`), so a STORED generated column `name_normalized`
 * holds LOWER(TRIM(name)) and a plain unique index sits on top of it. The
 * comparison is therefore case- and whitespace-insensitive, while the public
 * `name` column keeps the member's original capitalisation intact.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('users', 'name_normalized')) {
            DB::statement(
                'ALTER TABLE `users` ADD COLUMN `name_normalized` VARCHAR(255) '
                .'AS (LOWER(TRIM(`name`))) STORED'
            );
        }

        if (! $this->hasIndex('users', 'users_name_unique')) {
            DB::statement('ALTER TABLE `users` ADD UNIQUE INDEX `users_name_unique` (`name_normalized`)');
        }
    }

    public function down(): void
    {
        if ($this->hasIndex('users', 'users_name_unique')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropUnique('users_name_unique');
            });
        }

        if (Schema::hasColumn('users', 'name_normalized')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropColumn('name_normalized');
            });
        }
    }

    /** True when `$table` already carries an index named `$index`. */
    private function hasIndex(string $table, string $index): bool
    {
        foreach (DB::select("SHOW INDEX FROM `{$table}`") as $row) {
            if ($row->Key_name === $index) {
                return true;
            }
        }

        return false;
    }
};
