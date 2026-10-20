<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Community safety reports — members flagging malicious listings and accounts.
 *
 * The reportable is identified by a plain (`reportable_type`, `reportable_id`)
 * pair rather than an Eloquent morph, so the stored type is the stable
 * vocabulary the mobile client speaks — `listing` or `user` — and no internal
 * PHP class name is ever written to the database.
 *
 * `reporter_id` is nullable and nulls on delete ON PURPOSE: the moderation
 * trail must outlive the reporter's account. A member who deletes their
 * profile does not get to erase the reports a moderator still has to act on.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reports', function (Blueprint $table) {
            $table->id();

            // The member who filed the report. Null once their account is gone.
            $table->foreignId('reporter_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();

            // 'listing' | 'user' — the thing being reported.
            $table->string('reportable_type', 20);
            $table->unsignedBigInteger('reportable_id');

            // scam | inappropriate_content | counterfeit | harassment | other
            $table->string('reason', 40);

            // Optional free-text detail from the reporter.
            $table->text('description')->nullable();

            // pending | reviewed | action_taken
            $table->string('status', 20)->default('pending');

            // Moderator trail.
            $table->timestamp('reviewed_at')->nullable();
            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->text('resolution_note')->nullable();

            $table->timestamps();

            // The moderation queue reads by target ("every report against this
            // listing") far more often than by reporter.
            $table->index(['reportable_type', 'reportable_id']);
            $table->index('status');
            $table->index('reporter_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reports');
    }
};
