<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Tests\TestCase;

/**
 * Messenger-style message actions: copy is client-side, but edit and delete
 * are server-authorised.
 *
 * Two separate rules are enforced, and the tests below pin both:
 *   1. You must be a participant of the thread  → otherwise 404 (so message
 *      ids cannot be probed).
 *   2. You must be the sender of that message   → otherwise 403.
 *
 * These tests share the development database and run inside a transaction
 * that is rolled back (see backend/phpunit.xml).
 */
class MessageActionsTest extends TestCase
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

    private function thread(User ...$participants): Conversation
    {
        return Conversation::create([
            'participant_one_id' => $participants[0]->id,
            'participant_two_id' => $participants[1]->id,
        ]);
    }

    private function message(Conversation $conversation, User $sender, string $body = 'Original text'): Message
    {
        return $conversation->messages()->create([
            'sender_id' => $sender->id,
            'body' => $body,
        ]);
    }

    // ── Edit ────────────────────────────────────────────────────────────────

    public function test_the_sender_can_edit_their_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($buyer)
            ->putJson("/api/messages/{$message->id}", ['body' => 'Is this still available?'])
            ->assertOk()
            ->assertJsonPath('message.body', 'Is this still available?');

        $fresh = $message->fresh();
        $this->assertSame('Is this still available?', $fresh->body);
        $this->assertNotNull($fresh->edited_at, 'edited_at must be stamped.');
    }

    public function test_an_edited_message_reports_the_edit_marker(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($buyer)
            ->putJson("/api/messages/{$message->id}", ['body' => 'Revised'])
            ->assertOk()
            ->assertJsonPath('message.edited_at', fn ($value) => is_string($value) && $value !== '');

        // The thread read exposes the marker so the bubble can show "Edited".
        $this->actingAs($seller)
            ->getJson("/api/conversations/{$conversation->id}/messages")
            ->assertOk()
            ->assertJsonPath('messages.0.edited_at', fn ($value) => is_string($value));
    }

    public function test_the_recipient_cannot_edit_someone_elses_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($seller)
            ->putJson("/api/messages/{$message->id}", ['body' => 'Hijacked'])
            ->assertStatus(403);

        $this->assertSame('Original text', $message->fresh()->body);
    }

    public function test_a_non_participant_cannot_edit_a_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $stranger = $this->user('Stranger '.uniqid(), 'stranger-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        // 404, not 403 — the response must not confirm the message exists.
        $this->actingAs($stranger)
            ->putJson("/api/messages/{$message->id}", ['body' => 'Hijacked'])
            ->assertNotFound();

        $this->assertSame('Original text', $message->fresh()->body);
    }

    public function test_editing_rejects_an_empty_body(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($buyer)
            ->putJson("/api/messages/{$message->id}", ['body' => '   '])
            ->assertStatus(422);

        $this->assertSame('Original text', $message->fresh()->body);
    }

    public function test_editing_enforces_the_length_limit(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($buyer)
            ->putJson("/api/messages/{$message->id}", ['body' => str_repeat('x', 5001)])
            ->assertStatus(422)
            ->assertJsonValidationErrors('body');
    }

    public function test_an_unknown_message_id_is_a_404(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');

        $this->actingAs($buyer)
            ->putJson('/api/messages/999999999', ['body' => 'Hello'])
            ->assertNotFound();
    }

    // ── Delete ──────────────────────────────────────────────────────────────

    public function test_the_sender_can_delete_their_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($buyer)
            ->deleteJson("/api/messages/{$message->id}")
            ->assertOk()
            ->assertJsonPath('deleted', true);
    }

    public function test_a_deleted_message_disappears_from_the_thread_for_both_sides(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $keep = $this->message($conversation, $seller, 'Keep me');
        $drop = $this->message($conversation, $buyer, 'Remove me');

        $this->actingAs($buyer)->deleteJson("/api/messages/{$drop->id}")->assertOk();

        foreach ([$buyer, $seller] as $viewer) {
            $bodies = collect(
                $this->actingAs($viewer)
                    ->getJson("/api/conversations/{$conversation->id}/messages")
                    ->assertOk()
                    ->json('messages')
            )->pluck('body');

            $this->assertNotContains('Remove me', $bodies, 'The removed message must be gone.');
            $this->assertContains('Keep me', $bodies, 'Other messages must survive.');
        }
    }

    public function test_deleting_is_a_soft_delete_that_keeps_the_record(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer, 'Audit evidence');

        $this->actingAs($buyer)->deleteJson("/api/messages/{$message->id}")->assertOk();

        // The row must still exist server-side for the admin inquiry record.
        $this->assertDatabaseHas('messages', [
            'id' => $message->id,
            'body' => 'Audit evidence',
        ]);
        $this->assertNotNull(
            Message::withTrashed()->find($message->id)->deleted_at,
            'deleted_at must be stamped.',
        );
    }

    public function test_the_recipient_cannot_delete_someone_elses_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($seller)
            ->deleteJson("/api/messages/{$message->id}")
            ->assertStatus(403);

        $this->assertNull(
            Message::withTrashed()->find($message->id)->deleted_at,
        );
    }

    public function test_a_non_participant_cannot_delete_a_message(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $stranger = $this->user('Stranger '.uniqid(), 'stranger-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $message = $this->message($conversation, $buyer);

        $this->actingAs($stranger)
            ->deleteJson("/api/messages/{$message->id}")
            ->assertNotFound();

        $this->assertNull(
            Message::withTrashed()->find($message->id)->deleted_at,
        );
    }

    public function test_deleting_the_newest_message_repoints_the_inbox_timestamp(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);
        $older = $this->message($conversation, $buyer, 'Older');
        $newest = $this->message($conversation, $buyer, 'Newest');

        $conversation->update(['last_message_at' => $newest->created_at]);
        $this->actingAs($buyer)->deleteJson("/api/messages/{$newest->id}")->assertOk();

        $conversation->refresh();
        $this->assertTrue(
            $conversation->last_message_at->equalTo($older->created_at),
            'The inbox preview must fall back to the newest surviving message.',
        );
    }
}