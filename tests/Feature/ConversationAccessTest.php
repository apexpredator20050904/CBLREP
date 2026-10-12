<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Conversation;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Direct inquiries are private to their two participants.
 *
 * Every read and write routes through `ConversationController::ownedConversation`,
 * so a non-participant must get a 404 (not a 403 — that would confirm the
 * conversation exists).
 */
class ConversationAccessTest extends TestCase
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

    public function test_a_third_party_cannot_read_the_thread(): void
    {
        $buyer = $this->user('Buyer', 'buyer@example.test');
        $seller = $this->user('Seller', 'seller@example.test');
        $stranger = $this->user('Stranger', 'stranger@example.test');

        $conversation = Conversation::create([
            'participant_one_id' => $buyer->id,
            'participant_two_id' => $seller->id,
        ]);

        $this->actingAs($stranger)
            ->getJson("/api/conversations/{$conversation->id}/messages")
            ->assertNotFound();

        $this->actingAs($stranger)
            ->postJson("/api/conversations/{$conversation->id}/messages", ['body' => 'let me in'])
            ->assertNotFound();

        $this->assertDatabaseMissing('messages', ['body' => 'let me in']);
    }

    public function test_a_participant_can_read_and_send(): void
    {
        $buyer = $this->user('Buyer', 'buyer@example.test');
        $seller = $this->user('Seller', 'seller@example.test');

        $conversation = Conversation::create([
            'participant_one_id' => $buyer->id,
            'participant_two_id' => $seller->id,
        ]);

        $this->actingAs($seller)
            ->postJson("/api/conversations/{$conversation->id}/messages", ['body' => 'Yes, still available.'])
            ->assertCreated();

        $this->actingAs($buyer)
            ->getJson("/api/conversations/{$conversation->id}/messages")
            ->assertOk()
            ->assertJsonPath('messages.0.body', 'Yes, still available.');
    }

    public function test_members_cannot_inquire_about_their_own_listing(): void
    {
        $owner = $this->user('Owner', 'owner@example.test');
        $listing = $this->listing($owner);

        $this->actingAs($owner)
            ->postJson('/api/conversations', [
                'user_id' => $owner->id,
                'listing_id' => $listing->id,
            ])
            ->assertStatus(422);
    }

    public function test_the_listing_owner_must_match_the_messaging_member(): void
    {
        $owner = $this->user('Owner', 'owner@example.test');
        $other = $this->user('Other', 'other@example.test');
        $listing = $this->listing($owner);

        // Buyer addresses "other" but the listing belongs to "owner".
        $this->actingAs($other)
            ->postJson('/api/conversations', [
                'user_id' => $other->id,
                'listing_id' => $listing->id,
            ])
            ->assertStatus(422);
    }

    public function test_the_inbox_only_lists_your_own_threads(): void
    {
        $buyer = $this->user('Buyer', 'buyer@example.test');
        $seller = $this->user('Seller', 'seller@example.test');
        $stranger = $this->user('Stranger', 'stranger@example.test');

        Conversation::create([
            'participant_one_id' => $buyer->id,
            'participant_two_id' => $seller->id,
        ]);

        $response = $this->actingAs($stranger)->getJson('/api/conversations')->assertOk();
        $this->assertCount(0, $response->json('conversations'));

        $response = $this->actingAs($seller)->getJson('/api/conversations')->assertOk();
        $this->assertCount(1, $response->json('conversations'));
    }
}
