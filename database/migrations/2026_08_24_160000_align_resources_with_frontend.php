<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            if (! Schema::hasColumn('resources', 'exchange_type')) {
                $table->string('exchange_type')->default('Lend')->after('type');
            }
            if (! Schema::hasColumn('resources', 'condition')) {
                $table->string('condition')->default('Good')->after('exchange_type');
            }
            if (! Schema::hasColumn('resources', 'status')) {
                $table->string('status')->default('active')->after('is_active');
            }
        });
    }

    public function down(): void
    {
        Schema::table('resources', function (Blueprint $table) {
            $table->dropColumn(['exchange_type', 'condition', 'status']);
        });
    }
};
