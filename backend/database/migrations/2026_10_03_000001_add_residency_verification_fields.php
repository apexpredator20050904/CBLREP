<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Residency verification — strictly a submission & review workflow.
 *
 * Lifecycle:
 *   unverified → (member submits proof) → pending → (admin review) → verified
 *                                                              └──→ rejected
 *
 * Members begin `unverified`. Only a reviewed submission from the admin
 * Verification queue can move them to `verified`; there is no schema path
 * that flips a member straight to `verified` without a submitted document.
 */
return new class extends Migration
{
    public function up(): void
    {
        // The proof-of-residency image path (kept idempotent in case an older
        // environment already added it under a different migration history).
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'verification_document_path')) {
                $table->string('verification_document_path')->nullable()->after('is_verified');
            }
        });

        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'verification_submitted_at')) {
                $table->timestamp('verification_submitted_at')->nullable()->after('verification_document_path');
            }
            if (! Schema::hasColumn('users', 'verification_note')) {
                $table->text('verification_note')->nullable()->after('verification_submitted_at');
            }
        });

        // New members are unverified until they submit proof and an admin
        // reviews it — the default now reflects the start of the workflow.
        Schema::table('users', function (Blueprint $table) {
            $table->string('verification_status')->default('unverified')->change();
        });

        // Backfill: anyone still `pending` with no document on file has not
        // actually started the workflow, so normalise them to `unverified`.
        DB::table('users')
            ->where('is_verified', false)
            ->where('verification_status', 'pending')
            ->whereNull('verification_document_path')
            ->update(['verification_status' => 'unverified']);
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            foreach (['verification_note', 'verification_submitted_at'] as $column) {
                if (Schema::hasColumn('users', $column)) {
                    $table->dropColumn($column);
                }
            }

            $table->string('verification_status')->default('pending')->change();
        });
    }
};