<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Exchange;
use App\Models\MemberNotification;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Direct barter proposals — the send side.
 *
 * `POST /api/exchanges` existed and was fully validated, but no client ever
 * called it: members could only negotiate through chat. These tests pin the
 * proposal flow so a future change cannot quietly take it away.
 *
 * The invariants under test:
 *   - a proposal is always two-sided (no one-sided "gift" proposals);
 *   - you cannot propose against your own listing;
 *   - an offered listing must be yours;
 *   - the owner is notified.
 */
class ExchangeProposalTest extends TestCase
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

    public function test_proposal_with_an_offered_listing_reaches_the_owner(): void
    {
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $wanted = $this->listing($owner, 'A laptop');
        $offered = $this->listing($proposer, 'A bicycle');

        $this->actingAs($proposer)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'offered_resource_id' => $offered->id,
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated()
            ->assertJsonPath('message', 'Barter proposal sent.');

        $this->assertDatabaseHas('exchanges', [
            'resource_id' => $wanted->id,
            'offered_resource_id' => $offered->id,
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'status' => Exchange::STATUS_PENDING,
        ]);

        $this->assertDatabaseHas('member_notifications', [
            'user_id' => $owner->id,
            'type' => 'exchange_request',
        ]);
    }

    public function test_proposal_with_a_free_text_offer_is_accepted(): void
    {
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $wanted = $this->listing($owner, 'A guitar');

        // Skill-for-skill trades have no listing to attach — the free-text
        // field is the whole offer side.
        $this->actingAs($proposer)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'offered_item' => 'Guitar lessons',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated();

        $this->assertDatabaseHas('exchanges', [
            'resource_id' => $wanted->id,
            'offered_item' => 'Guitar lessons',
            'offered_resource_id' => null,
        ]);
    }

    public function test_a_one_sided_proposal_is_rejected(): void
    {
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $wanted = $this->listing($owner, 'A desk');

        // The suite runs against the shared development database with
        // DatabaseTransactions (see RUNNING.md §5.5a), so other exchanges —
        // demo/seed data included — may already exist. Assert the *intent*
        // (no new row was written) rather than a global count of zero.
        $before = Exchange::count();

        // No offered_resource_id and no offered_item — this is a request for
        // a free gift, not a barter.
        $this->actingAs($proposer)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('offered_item');

        $this->assertSame($before, Exchange::count());
    }

    public function test_a_member_cannot_propose_against_their_own_listing(): void
    {
        $owner = $this->member('owner@example.test');
        $wanted = $this->listing($owner, 'A monitor');

        $this->actingAs($owner)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'offered_item' => 'A keyboard',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422);
    }

    public function test_an_offered_listing_must_belong_to_the_proposer(): void
    {
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $wanted = $this->listing($owner, 'A printer');
        $someoneElses = $this->listing($this->member('third@example.test'), 'A scanner');

        $this->actingAs($proposer)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'offered_resource_id' => $someoneElses->id,
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertStatus(422);
    }

    public function test_meetup_location_is_required(): void
    {
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $wanted = $this->listing($owner, 'A chair');

        $this->actingAs($proposer)
            ->postJson('/api/exchanges', [
                'resource_id' => $wanted->id,
                'offered_item' => 'A stool',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['barangay', 'purok_sitio']);
    }
}
