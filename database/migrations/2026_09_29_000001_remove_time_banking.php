<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Removes the Time-Banking Credits feature from the CBLRE schema.
 *
 * Time banking was retired in favour of the three remaining exchange models
 * (freecycling, bartering and temporary lending). The original create
 * migrations are intentionally left on disk as history; this forward migration
 * tears the structures back out so an already-migrated database and a fresh
 * `php artisan migrate` both converge on the same credit-free schema.
 *
 * Dropped:
 *   timebank_transactions  service-request ledger (the "hours" ledger)
 *   timebank_services      catalogue of skills/services offered for hours
 *   time_credits           per-user credit ledger + transfers
 *   users.time_bank_credits        member credit balance
 *   exchanges.credits_exchanged     credit value attached to an exchange
 */
return new class extends Migration
{
    public function up(): void
    {
        // Historical time_banking exchange rows are meaningless without credits.
        DB::table('exchanges')->where('exchange_type', 'time_banking')->delete();

        Schema::dropIfExists('timebank_transactions');
        Schema::dropIfExists('timebank_services');
        Schema::dropIfExists('time_credits');

        if (Schema::hasColumn('users', 'time_bank_credits')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropColumn('time_bank_credits');
            });
        }

        if (Schema::hasColumn('exchanges', 'credits_exchanged')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->dropColumn('credits_exchanged');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasColumn('users', 'time_bank_credits')) {
            Schema::table('users', function (Blueprint $table) {
                $table->decimal('time_bank_credits', 8, 2)->default(0);
            });
        }

        if (! Schema::hasColumn('exchanges', 'credits_exchanged')) {
            Schema::table('exchanges', function (Blueprint $table) {
                $table->decimal('credits_exchanged', 8, 2)->default(0);
            });
        }

        if (! Schema::hasTable('time_credits')) {
            Schema::create('time_credits', function (Blueprint $table) {
                $table->id();
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->foreignId('counterparty_id')->nullable()->constrained('users')->nullOnDelete();
                $table->decimal('amount', 8, 2);
                $table->string('type', 30);
                $table->string('description')->nullable();
                $table->nullableMorphs('reference');
                $table->timestamps();
                $table->index(['user_id', 'created_at']);
            });
        }

        if (! Schema::hasTable('timebank_services')) {
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
        }

        if (! Schema::hasTable('timebank_transactions')) {
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
    }
};
