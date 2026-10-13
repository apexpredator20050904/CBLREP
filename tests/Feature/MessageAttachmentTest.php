<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Message;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Messenger-style message attachments: photo/document sharing over
 * multipart/form-data into storage/app/public/chat_attachments.
 */
class MessageAttachmentTest extends TestCase
{
    private function user(string $prefix): User
    {
        $tag = uniqid();
        return User::create([
            'name' => $prefix.' '.$tag,
            'email' => strtolower($prefix).'-'.$tag.'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
        ]);
    }

    private function thread(User $a, User $b): Conversation
    {
        return Conversation::create([
            'participant_one_id' => $a->id,
            'participant_two_id' => $b->id,
        ]);
    }

    public function test_a_participant_can_send_a_photo_attachment(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            [
                'body' => 'See this photo',
                'file' => UploadedFile::fake()->create('photo.jpg', 50, 'image/jpeg'),
            ]
        );

        $response->assertCreated()
            ->assertJsonPath('message.file_type', 'image')
            ->assertJsonPath('message.file_name', 'photo.jpg');

        $path = $response->json('message.file_path');
        $this->assertNotEmpty($path);
        Storage::disk('public')->assertExists($path);
    }

    public function test_a_participant_can_send_a_document_without_text(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $conversation = $this->thread($buyer, $seller);

        $response = $this->actingAs($seller)->post(
            "/api/conversations/{$conversation->id}/messages",
            [
                'file' => UploadedFile::fake()->create('terms.pdf', 50, 'application/pdf'),
            ]
        );

        $response->assertCreated()
            ->assertJsonPath('message.file_type', 'document');

        Storage::disk('public')->assertExists($response->json('message.file_path'));
    }

    public function test_direct_post_messages_accepts_multipart_attachments(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)->post(
            '/api/messages',
            [
                'conversation_id' => $conversation->id,
                'body' => 'Direct upload',
                'file' => UploadedFile::fake()->create('note.txt', 5, 'text/plain'),
            ]
        )->assertCreated()->assertJsonPath('message.file_type', 'document');
    }

    public function test_sending_neither_text_nor_file_is_rejected(): void
    {
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)
            ->postJson("/api/conversations/{$conversation->id}/messages", ['body' => '   '])
            ->assertStatus(422);
    }

    public function test_disallowed_file_types_are_rejected(): void
    {
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($buyer)->post(
            "/api/conversations/{$conversation->id}/messages",
            ['file' => UploadedFile::fake()->create('run.exe', 10, 'application/x-msdownload')]
        )->assertStatus(422);
    }

    public function test_a_non_participant_cannot_attach_to_the_thread(): void
    {
        Storage::fake('public');
        $buyer = $this->user('Buyer');
        $seller = $this->user('Seller');
        $stranger = $this->user('Stranger');
        $conversation = $this->thread($buyer, $seller);

        $this->actingAs($stranger)->post(
            "/api/conversations/{$conversation->id}/messages",
            [
                'body' => 'Hijack',
                'file' => UploadedFile::fake()->create('evil.jpg', 10, 'image/jpeg'),
            ]
        )->assertNotFound();
    }
}
