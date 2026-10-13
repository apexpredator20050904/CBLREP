<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Structured location fields (barangay + purok/sitio) on the three tables
 * that carry member or transaction location data.
 *
 * `barangay` is the one of the 20 official Trinidad, Bohol barangays
 * (validated at the application layer against App\Support\Barangays);
 * `purok_sitio` is the specific purok or sitio inside that barangay.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'barangay')) {
                $table->string('barangay')->nullable()->index()->after('barangay_or_location');
            }
            if (! Schema::hasColumn('users', 'purok_sitio')) {
                $table->string('purok_sitio')->nullable()->after('barangay');
            }
        });

        Schema::table('resources', function (Blueprint $table) {
            if (! Schema::hasColumn('resources', 'barangay')) {
                $table->string('barangay')->nullable()->index()->after('location');
            }
            if (! Schema::hasColumn('resources', 'purok_sitio')) {
                $table->string('purok_sitio')->nullable()->after('barangay');
            }
        });

        Schema::table('exchanges', function (Blueprint $table) {
            if (! Schema::hasColumn('exchanges', 'barangay')) {
                $table->string('barangay')->nullable()->index()->after('status');
            }
            if (! Schema::hasColumn('exchanges', 'purok_sitio')) {
                $table->string('purok_sitio')->nullable()->after('barangay');
            }
        });

        // Backfill: the legacy free-text columns were the only source of
        // location before this migration, so carry them forward when they
        // already name an official barangay.
        $official = \App\Support\Barangays::ALL;

        DB::table('users')->select('id', 'barangay_or_location')->whereNull('barangay')
            ->orderBy('id')->chunkById(500, function ($rows) use ($official) {
                foreach ($rows as $row) {
                    foreach ($official as $barangay) {
                        if ($row->barangay_or_location && stripos($row->barangay_or_location, $barangay) !== false) {
                            DB::table('users')->where('id', $row->id)->update(['barangay' => $barangay]);
                            break;
                        }
                    }
                }
            });

        DB::table('resources')->select('id', 'location')->whereNull('barangay')
            ->orderBy('id')->chunkById(500, function ($rows) use ($official) {
                foreach ($rows as $row) {
                    foreach ($official as $barangay) {
                        if ($row->location && stripos($row->location, $barangay) !== false) {
                            DB::table('resources')->where('id', $row->id)->update(['barangay' => $barangay]);
                            break;
                        }
                    }
                }
            });
    }

    public function down(): void
    {
        foreach (['users', 'resources', 'exchanges'] as $table) {
            Schema::table($table, function (Blueprint $blueprint) use ($table) {
                foreach (['purok_sitio', 'barangay'] as $column) {
                    if (Schema::hasColumn($table, $column)) {
                        $blueprint->dropColumn($column);
                    }
                }
            });
        }
    }
};
