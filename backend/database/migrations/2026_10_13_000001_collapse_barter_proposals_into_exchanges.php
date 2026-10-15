<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Collapses `barter_proposals` into `exchanges`.
 *
 * Two models described the same thing — an item-for-item trade between two
 * members — and both were live. `BarterProposal` was the earlier, lighter
 * sketch: no transition validation, no dual-confirmation, no audit trail.
 * `Exchange` is the mature one: an adjacency-list state machine, per-party
 * authority, dual-confirmation on completion, barangay/purok_sitio, and the
 * admin approval workflow.
 *
 * Keeping both meant two state machines for one concept, and the lighter one
 * was a trap: a client could still create a "proposal" that bypassed every
 * control the real flow enforces.
 *
 * Every existing row is carried across with the field mapping below, so no
 * in-flight trade is lost, and the old table is then dropped. From here on
 * `Exchange` is the single authoritative definition of a barter.
 *
 * Column mapping (barter_proposals → exchanges):
 *   sender_id        → receiver_id          (the proposer)
 *   receiver_id      → provider_id          (owner of the wanted listing)
 *   requested_item_id → resource_id         (the listing being asked for)
 *   offered_item_id  → offered_resource_id  (what the proposer gives back)
 *   status           → status              (identical vocabulary)
 */
return new class extends Migration
{
    public function up(): void
    {
        // Guarded so the migration is safe to re-run on a database where the
        // backfill already completed (and on one where it never ran).
        if (Schema::hasTable('barter_proposals') && Schema::hasTable('exchanges')) {
            DB::transaction(function () {
                DB::statement(
                    'INSERT INTO `exchanges`
                        (`resource_id`, `offered_resource_id`, `offered_item`,
                         `provider_id`, `receiver_id`, `exchange_type`, `status`,
                         `barangay`, `purok_sitio`, `created_at`, `updated_at`)
                    SELECT
                        `requested_item_id`,
                        `offered_item_id`,
                        NULL,
                        `receiver_id`,
                        `sender_id`,
                        "barter",
                        bp.`status`,
                        COALESCE(r.`barangay`, "Poblacion"),
                        COALESCE(r.`purok_sitio`, ""),
                        bp.`created_at`,
                        bp.`updated_at`
                    FROM `barter_proposals` bp
                    LEFT JOIN `resources` r ON r.`id` = bp.`requested_item_id`
                    WHERE NOT EXISTS (
                        SELECT 1 FROM `exchanges` e
                        WHERE e.`resource_id` = bp.`requested_item_id`
                          AND e.`offered_resource_id` = bp.`offered_item_id`
                          AND e.`provider_id` = bp.`receiver_id`
                          AND e.`receiver_id` = bp.`sender_id`
                    )'
                );

                DB::table('barter_proposals')->delete();
            });
        }

        Schema::dropIfExists('barter_proposals');
    }

    public function down(): void
    {
        // The collapse is deliberately not reversed. `barter_proposals` had no
        // transition validation or dual-confirmation, so restoring it would
        // reintroduce the weaker of the two state machines. Rolls-forward
        // migrations only, like every other migration in this project.
    }
};
