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
        Schema::create('exchanges', function (Blueprint $table) {
            $table->id();
            $table->foreignId('resource_id')->nullable()->constrained('resources')->nullOnDelete();
            $table->foreignId('provider_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('receiver_id')->constrained('users')->cascadeOnDelete();

            // lending | barter | freecycle | time_banking
            $table->string('exchange_type')->default('lending');

            // pending | accepted | completed | cancelled
            $table->string('status')->default('pending');

            $table->date('scheduled_return_date')->nullable();
            $table->decimal('credits_exchanged', 8, 2)->default(0);
            $table->timestamps();

            $table->index(['provider_id', 'receiver_id']);
            $table->index('exchange_type');
            $table->index('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('exchanges');
    }
};
