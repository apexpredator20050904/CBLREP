<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Member profile photos.
 *
 * A display avatar is a trust/recognition aid for a neighbourhood barter
 * portal — neighbours recognise each other and throwaway accounts look less
 * anonymous. It is deliberately separate from residency verification: a photo
 * does not prove identity, the proof-of-residency document does. A photo is
 * merely *encouraged* when a member submits that document.
 *
 * Stored on the public disk so the app and the React admin console can render
 * it directly; unlike verification documents it carries nothing sensitive.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'avatar_path')) {
                $table->string('avatar_path')->nullable()->after('name');
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'avatar_path')) {
                $table->dropColumn('avatar_path');
            }
        });
    }
};
