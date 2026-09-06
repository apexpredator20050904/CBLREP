<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('timebank_services', function (Blueprint $table) {
            $table->id();
            $table->string('provider_email');
            $table->string('provider_name');
            $table->string('title');
            $table->text('description')->nullable();
            $table->string('category')->default('Skills');
            $table->decimal('estimated_hours', 6, 2)->default(1);
            $table->string('location')->nullable();
            $table->string('availability')->nullable();
            $table->string('status')->default('open');
            $table->timestamps();

            $table->index('provider_email');
            $table->index('status');
        });

        Schema::create('timebank_transactions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('service_id');
            $table->string('service_title');
            $table->string('provider_email');
            $table->string('provider_name');
            $table->string('requester_email');
            $table->string('requester_name');
            $table->string('barangay')->nullable();
            $table->decimal('requested_hours', 6, 2)->default(1);
            $table->decimal('hours_completed', 6, 2)->default(0);
            $table->decimal('credits_transferred', 6, 2)->default(0);
            $table->string('status')->default('Pending');
            $table->string('confirmation_status')->default('pending');
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->index(['provider_email', 'requester_email']);
            $table->index('service_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('timebank_transactions');
        Schema::dropIfExists('timebank_services');
    }
};
