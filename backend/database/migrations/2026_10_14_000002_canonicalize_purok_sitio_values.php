<?php

use App\Support\Puroks;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Fold every stored `purok_sitio` into its canonical form.
 *
 * The rule has always forced a "Purok …"/"Sitio …" shape, so most rows are
 * already close; this sweeps the stragglers ("purok 3", "PUROK  Poblacion",
 * a dropped separator) so casing and spacing can no longer fragment one purok
 * into several near-identical values in grouping and search. It only ever
 * rewrites; a value that canonicalises to nothing is left untouched, so no
 * location data is ever dropped.
 */
return new class extends Migration
{
    private const TABLES = ['users', 'resources', 'exchanges'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            DB::table($table)
                ->select('id', 'purok_sitio')
                ->whereNotNull('purok_sitio')
                ->chunkById(500, function ($rows) use ($table) {
                    foreach ($rows as $row) {
                        $canonical = Puroks::canonicalize($row->purok_sitio);

                        if ($canonical !== null && $canonical !== $row->purok_sitio) {
                            DB::table($table)->where('id', $row->id)->update(['purok_sitio' => $canonical]);
                        }
                    }
                });
        }
    }

    public function down(): void
    {
        // Irreversible by design: the original casing/spacing carried no
        // meaning and cannot be reconstructed. Nothing to undo.
    }
};
