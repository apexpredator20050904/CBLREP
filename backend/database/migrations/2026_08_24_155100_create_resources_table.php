<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('resources', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('category_id')->nullable()->constrained('categories')->nullOnDelete();

            // offer | request
            $table->string('type')->default('offer');

            // Aligned with the frontend listing form (see 2026_08_24_160000
            // align_resources_with_frontend, which guards these columns).
            $table->string('exchange_type')->default('Lend');
            $table->string('condition')->default('Good');

            $table->string('title');
            $table->text('description')->nullable();
            $table->string('location')->nullable();

            $table->boolean('is_active')->default(true);
            // active | pending | flagged | hidden | removed | closed
            $table->string('status')->default('active');

            $table->timestamps();

            $table->index(['user_id', 'is_active']);
            $table->index('status');
            $table->index('type');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('resources');
    }
};
