<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * item-for-item barter proposals.
 *
 * A proposal is always two-sided: the sender offers one of their own
 * listings (`offered_item_id`) in exchange for a specific listing owned
 * by the receiver (`requested_item_id`).
 *
 * Lifecycle: pending → accepted | rejected → completed
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('barter_proposals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('receiver_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('offered_item_id')->constrained('resources')->cascadeOnDelete();
            $table->foreignId('requested_item_id')->constrained('resources')->cascadeOnDelete();
            $table->string('status')->default('pending'); // pending | accepted | rejected | completed
            $table->timestamps();

            $table->index(['sender_id', 'status']);
            $table->index(['receiver_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('barter_proposals');
    }
};
