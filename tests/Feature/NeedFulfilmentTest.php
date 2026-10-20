<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Fulfilling a NEED — the mirrored side of a barter.
 *
 * When a neighbour answers a NEED ("I have what you need") the two roles
 * swap compared with a trade:
 *
 *   TRADE      → the proposer is the DEMANDER, the owner is the supplier.
 *                 provider = owner, receiver = proposer.
 *   FULFILMENT → the proposer is the SUPPLIER, the owner is the demander.
 *                 provider = proposer, receiver = owner.
 *
 * The state machine, the dual confirmation and the notifications are shared.
 * What changes is who may accept — always the member who posted the listing,
 * which on a need is the person deciding whether to take what is being
 * brought.
 */
class NeedFulfilmentTest extends TestCase
{
    private function member(string $email): User
    {
        return User::create([
            'name' => 'Test Member '.uniqid(),
            'email' => $email,
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    /** A NEED posted by $owner: "I want rice, I can trade 2 hours of childcare". */
    private function need(User $owner, string $title = 'Rice'): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Food'])->id,
            'type' => 'request',
            'compensation_type' => 'barter',
            'wanted_item' => '2 hours of childcare',
            'quantity' => '5 kg',
            'title' => $title,
            'description' => '',
            'condition' => 'Any',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    public function test_a_claim_on_a_need_swaps_the_two_roles(): void
    {
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        $this->actingAs($supplier)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated()
            ->assertJsonPath('exchange.kind', 'fulfilment')
            ->assertJsonPath('exchange.role', 'proposer');

        // The supplier is the provider here, and the poster the receiver.
        $this->assertDatabaseHas('exchanges', [
            'resource_id' => $need->id,
            'provider_id' => $supplier->id,
            'receiver_id' => $poster->id,
            'status' => Exchange::STATUS_PENDING,
        ]);
    }

    public function test_the_poster_decides_and_the_supplier_cannot(): void
    {
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        $id = $this->actingAs($supplier)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated()
            ->json('exchange.id');

        // The supplier cannot accept their own fulfilment.
        $this->actingAs($supplier)
            ->patchJson("/api/exchanges/{$id}", ['status' => 'accepted'])
            ->assertStatus(403);

        // The poster — the member who wrote the NEED — decides.
        $this->actingAs($poster)
            ->patchJson("/api/exchanges/{$id}", ['status' => 'accepted'])
            ->assertStatus(200)
            ->assertJsonPath('exchange.can_respond', false);

        $this->assertDatabaseHas('exchanges', [
            'id' => $id,
            'status' => Exchange::STATUS_ACCEPTED,
        ]);
    }

    public function test_both_parties_confirm_the_handover_and_the_need_closes(): void
    {
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        $id = $this->actingAs($supplier)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated()
            ->json('exchange.id');

        $this->actingAs($poster)
            ->patchJson("/api/exchanges/{$id}", ['status' => 'accepted'])
            ->assertStatus(200);

        // The supplier confirms the handover…
        $this->actingAs($supplier)
            ->postJson("/api/exchanges/{$id}/confirm-completion")
            ->assertStatus(200)
            ->assertJsonPath('exchange.i_confirmed', true)
            ->assertJsonPath('exchange.owner_confirmed', false)
            ->assertJsonPath('exchange.raw_status', 'accepted');

        // …and the poster confirms the receipt. Now it is complete and the
        // need leaves the feed.
        $this->actingAs($poster)
            ->postJson("/api/exchanges/{$id}/confirm-completion")
            ->assertStatus(200)
            ->assertJsonPath('exchange.raw_status', 'completed');

        $this->assertDatabaseHas('exchanges', [
            'id' => $id,
            'status' => Exchange::STATUS_COMPLETED,
            'proposer_confirmed' => true,
            'owner_confirmed' => true,
        ]);

        $this->assertDatabaseHas('resources', [
            'id' => $need->id,
            'is_active' => false,
            'status' => 'traded',
        ]);
    }

    public function test_the_supplier_cannot_fulfil_their_own_need(): void
    {
        $poster = $this->member('poster@example.test');
        $need = $this->need($poster);

        $this->actingAs($poster)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422);
    }

    public function test_a_paid_need_is_answered_in_chat_not_with_an_exchange(): void
    {
        // Money has no "return side", so a paid request cannot be answered by
        // a recorded two-sided exchange — the app sends a price quote in the
        // listing's chat thread instead.
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);
        $need->update(['compensation_type' => 'paid', 'price' => 300]);

        $this->actingAs($supplier)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422);
    }

    public function test_the_exchange_ledger_splits_by_direction(): void
    {
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        $this->actingAs($supplier)
            ->postJson('/api/exchanges', [
                'resource_id' => $need->id,
                'offered_item' => '2 hours of childcare',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated();

        // The supplier SENT the fulfilment; the poster RECEIVED it.
        $this->actingAs($supplier)
            ->getJson('/api/exchanges')
            ->assertJsonPath('metrics.proposalsSent', 1)
            ->assertJsonPath('metrics.proposalsReceived', 0);

        $this->actingAs($poster)
            ->getJson('/api/exchanges')
            ->assertJsonPath('metrics.proposalsSent', 0)
            ->assertJsonPath('metrics.proposalsReceived', 1);
    }

    public function test_the_model_reports_the_direction_of_an_exchange(): void
    {
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        $exchange = Exchange::create([
            'resource_id' => $need->id,
            'offered_item' => '2 hours of childcare',
            'provider_id' => $supplier->id,
            'receiver_id' => $poster->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
        $exchange->load('resource');

        $this->assertTrue($exchange->isNeed());
        $this->assertSame($supplier->id, $exchange->proposerId());
        $this->assertSame($poster->id, $exchange->ownerId());
    }
}
