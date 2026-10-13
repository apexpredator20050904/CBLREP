<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * One authoritative definition of a barter.
 *
 * `barter_proposals` and `exchanges` used to describe the same thing — an
 * item-for-item trade — as two tables with two state machines. The lighter one
 * allowed single-party completion, skipped transition validation and had no
 * audit trail, and it was still creatable by any client, so it was a way
 * around every control the real flow enforced.
 *
 * Migration 2026_10_13_000001 folded every row into `exchanges` and dropped
 * the table. `Exchange` is now the only model; the old `/api/barter-proposals`
 * routes survive as aliases so existing clients keep working.
 */
class BarterCollapseTest extends TestCase
{
    private function user(string $name, string $email): User
    {
        return User::create([
            'name' => $name,
            'email' => $email,
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
        ]);
    }

    private function listing(User $owner, string $title = 'A drill'): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => $title,
            'description' => '',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    public function test_the_barter_proposals_table_no_longer_exists(): void
    {
        $this->assertFalse(
            Schema::hasTable('barter_proposals'),
            'The collapsed table must be gone, otherwise two models still describe a barter.',
        );
    }

    public function test_the_alias_lists_incoming_and_outgoing_trades(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $proposer = $this->user('Proposer '.uniqid(), 'proposer-'.uniqid().'@example.test');
        $wanted = $this->listing($owner);
        $offered = $this->listing($proposer, 'A returned lamp');

        Exchange::create([
            'resource_id' => $wanted->id,
            'offered_resource_id' => $offered->id,
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        // The owner was asked to trade → incoming.
        $asOwner = $this->actingAs($owner)->getJson('/api/barter-proposals')->assertOk();
        $this->assertCount(1, $asOwner->json('incoming'));
        $this->assertCount(0, $asOwner->json('outgoing'));

        // The proposer asked → outgoing.
        $asProposer = $this->actingAs($proposer)->getJson('/api/barter-proposals')->assertOk();
        $this->assertCount(0, $asProposer->json('incoming'));
        $this->assertCount(1, $asProposer->json('outgoing'));
    }

    public function test_the_alias_payload_matches_the_legacy_client_contract(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $proposer = $this->user('Proposer '.uniqid(), 'proposer-'.uniqid().'@example.test');
        $wanted = $this->listing($owner, 'The wanted chair');
        $offered = $this->listing($proposer, 'The offered stool');

        Exchange::create([
            'resource_id' => $wanted->id,
            'offered_resource_id' => $offered->id,
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        $row = $this->actingAs($proposer)
            ->getJson('/api/barter-proposals')
            ->assertOk()
            ->json('outgoing.0');

        // Read by both the Flutter inbox and the admin Barter Requests page.
        foreach (['id', 'direction', 'status', 'raw_status', 'counterparty', 'created_at'] as $key) {
            $this->assertArrayHasKey($key, $row, "Legacy client expects '$key'.");
        }
        $this->assertSame('outgoing', $row['direction']);
        $this->assertSame($owner->name, $row['counterparty']);
        $this->assertSame('The offered stool', $row['offered_item']['title']);
        $this->assertSame('The wanted chair', $row['requested_item']['title']);

        // The admin Exchanges page reads these off the same row.
        foreach (['item', 'offered', 'withUser', 'role', 'can_respond'] as $key) {
            $this->assertArrayHasKey($key, $row, "Admin Exchanges page expects '$key'.");
        }
        // Viewed by the proposer: they asked, so they cannot respond — only the
// owner of the wanted listing can.
        $this->assertSame('proposer', $row['role']);
        $this->assertFalse($row['can_respond'], 'Only the listing owner can respond.');
        $this->assertTrue($row['can_cancel'], 'The proposer can still walk away.');
    }

    public function test_completing_through_the_alias_requires_both_parties(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $proposer = $this->user('Proposer '.uniqid(), 'proposer-'.uniqid().'@example.test');
        $wanted = $this->listing($owner);
        $offered = $this->listing($proposer);

        $exchange = Exchange::create([
            'resource_id' => $wanted->id,
            'offered_resource_id' => $offered->id,
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        // The old barter flow let one party complete a trade outright. That
        // transition is gone: pending cannot jump to completed.
        $this->actingAs($owner)
            ->patchJson("/api/barter-proposals/{$exchange->id}/status", ['status' => 'completed'])
            ->assertStatus(422);

        // Accept, then one confirmation — still not complete.
        $this->actingAs($owner)
            ->patchJson("/api/barter-proposals/{$exchange->id}/status", ['status' => 'accepted'])
            ->assertOk();

        $this->actingAs($proposer)
            ->patchJson("/api/barter-proposals/{$exchange->id}/status", ['status' => 'completed'])
            ->assertOk()
            ->assertJsonPath('exchange.raw_status', 'accepted');

        // Only when the second party confirms does the trade complete.
        $this->actingAs($owner)
            ->patchJson("/api/barter-proposals/{$exchange->id}/status", ['status' => 'completed'])
            ->assertOk()
            ->assertJsonPath('exchange.raw_status', 'completed');

        $this->assertDatabaseHas('resources', [
            'id' => $wanted->id,
            'is_active' => false,
            'status' => 'traded',
        ]);
    }

    public function test_the_recipient_cannot_accept_a_trade(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $proposer = $this->user('Proposer '.uniqid(), 'proposer-'.uniqid().'@example.test');
        $wanted = $this->listing($owner);
        $offered = $this->listing($proposer);

        $exchange = Exchange::create([
            'resource_id' => $wanted->id,
            'offered_resource_id' => $offered->id,
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        // Accepting is the listing owner's call only.
        $this->actingAs($proposer)
            ->patchJson("/api/barter-proposals/{$exchange->id}/status", ['status' => 'accepted'])
            ->assertStatus(403);
    }

    public function test_a_created_exchange_is_two_sided(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $proposer = $this->user('Proposer '.uniqid(), 'proposer-'.uniqid().'@example.test');
        $wanted = $this->listing($owner);

        // The old barter endpoint accepted a proposal with no return side.
        // The alias delegates to ExchangeController::store, which requires one.
        $this->actingAs($proposer)
            ->postJson('/api/barter-proposals', [
                'resource_id' => $wanted->id,
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('offered_item');
    }

    public function test_a_proposal_cannot_target_your_own_listing(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $wanted = $this->listing($owner);

        $this->actingAs($owner)
            ->postJson('/api/barter-proposals', [
                'resource_id' => $wanted->id,
                'offered_item' => 'A returned lamp',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422);
    }
}