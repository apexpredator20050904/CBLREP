<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('exchanges', function (Blueprint $table) {
            $table->date('return_date')->nullable()->after('scheduled_return_date');
            $table->index(['receiver_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::table('exchanges', function (Blueprint $table) {
            $table->dropIndex(['receiver_id', 'status']);
            $table->dropColumn('return_date');
        });
    }
};
