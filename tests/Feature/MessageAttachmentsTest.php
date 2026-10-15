<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Messenger-style attachments: photos and documents sent as
 * multipart/form-data, stored under `chat_attachments`, and exposed in
 * `toChatPayload()` as file_url/file_type/file_name/file_size/mime_type.
 */
class MessageAttachmentsTest extends TestCase
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

    public function test_sending_an_image_stores_it_and_returns_its_url(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['body' => 'Look at this item', 'file' => UploadedFile::fake()->create('photo.jpg', 200, 'image/jpeg')]
        );

        $response->assertCreated();
        $message = $response->json('message');
        $this->assertSame('image', $message['file_type']);
        $this->assertNotEmpty($message['file_url']);
        $this->assertSame('photo.jpg', $message['file_name']);

        /** @var Message $stored */
        $stored = Message::findOrFail($message['id']);
        Storage::disk('public')->assertExists($stored->file_path);
        $this->assertStringStartsWith('chat_attachments/', $stored->file_path);
    }

    public function test_sending_a_document_without_a_caption_is_allowed(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('notes.pdf', 50, 'application/pdf')]
        );

        $response->assertCreated();
        $this->assertSame('document', $response->json('message.file_type'));
        $this->assertSame('', $response->json('message.body'));
    }

    public function test_sending_neither_text_nor_file_is_rejected(): void
    {
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)
            ->postJson("/api/conversations/{$conversation->id}/messages", ['body' => '   '])
            ->assertStatus(422);
    }

    public function test_disallowed_file_types_are_rejected(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('run.exe', 50, 'application/x-msdownload')]
        )->assertStatus(422);
    }

    public function test_direct_post_messages_accepts_multipart_attachments(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($seller)->post('/api/messages', [
            'conversation_id' => $conversation->id,
            'body' => 'Terms attached',
            'file' => UploadedFile::fake()->create('terms.pdf', 80, 'application/pdf'),
        ]);

        $response->assertCreated();
        $this->assertSame('document', $response->json('message.file_type'));
        $this->assertSame('terms.pdf', $response->json('message.file_name'));
    }

    public function test_a_stranger_cannot_attach_to_someone_elses_thread(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $stranger = $this->user('Stranger '.uniqid(), 'stranger-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($stranger)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('notes.pdf', 50, 'application/pdf')]
        )->assertNotFound();
    }

    public function test_thread_read_exposes_attachment_fields(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('notes.pdf', 50, 'application/pdf')]
        )->assertCreated();

        $this->actingAs($seller)
            ->getJson("/api/conversations/{$conversation->id}/messages")
            ->assertOk()
            ->assertJsonPath('messages.0.file_type', 'document')
            ->assertJsonPath('messages.0.file_name', 'notes.pdf');
    }

    public function test_sending_a_video_stores_it_and_marks_it_video(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('walkaround.mp4', 5000, 'video/mp4')]
        );

        $response->assertCreated();
        $this->assertSame('video', $response->json('message.file_type'));
        $this->assertSame('walkaround.mp4', $response->json('message.file_name'));
        $this->assertNotEmpty($response->json('message.file_url'));

        /** @var Message $stored */
        $stored = Message::findOrFail($response->json('message.id'));
        Storage::disk('public')->assertExists($stored->file_path);
    }

    public function test_a_mov_video_is_accepted(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('clip.mov', 800, 'video/quicktime')]
        )->assertCreated()->assertJsonPath('message.file_type', 'video');
    }

    public function test_a_video_over_the_50mb_cap_is_rejected(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        // 52000 KB is just above the 51200 KB (50 MB) ceiling.
        $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('huge.mp4', 52000, 'video/mp4')]
        )->assertStatus(422);
    }

    public function test_video_is_not_treated_as_an_image(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer '.uniqid(), 'buyer-'.uniqid().'@example.test');
        $seller = $this->user('Seller '.uniqid(), 'seller-'.uniqid().'@example.test');
        $conversation = $this->thread($buyer, $seller);

        $body = UploadedFile::fake()->create('clip.mp4', 400, 'video/mp4');
        $response = $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => $body]
        );
        $response->assertCreated();

        // Look up by the returned id (not `latest()`) — this suite runs inside
        // a transaction against the shared dev DB, so another message could
        // have been inserted concurrently by the running app.
        /** @var Message $stored */
        $stored = Message::findOrFail($response->json('message.id'));
        $this->assertTrue($stored->isVideo());
        $this->assertFalse($stored->isImage());
    }
}
