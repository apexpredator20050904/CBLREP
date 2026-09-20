<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Captures student-specific verification data so admins can verify
 * Trinidad residents who are students at a local school or university.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'student_status')) {
                $table->boolean('student_status')->default(false)
                    ->after('barangay_or_location');
            }
            if (! Schema::hasColumn('users', 'student_school')) {
                $table->string('student_school')->nullable()
                    ->after('student_status');
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'student_school')) {
                $table->dropColumn('student_school');
            }
            if (Schema::hasColumn('users', 'student_status')) {
                $table->dropColumn('student_status');
            }
        });
    }
};
