<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('verification_document_path')->nullable();
            $table->string('verification_document_type')->nullable();
        });
        Schema::table('resources', function (Blueprint $table) {
            $table->string('image_path')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('resources', fn (Blueprint $table) => $table->dropColumn('image_path'));
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['verification_document_path', 'verification_document_type']);
        });
    }
};
