<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Member profile photos (Phase 1).
 *
 * A display avatar is a recognition aid, deliberately separate from residency
 * verification. These tests pin the contract the mobile app and the React admin
 * console rely on:
 *   - a member can set / replace / remove their own photo,
 *   - replacing deletes the previous file (avatars must not accumulate),
 *   - only real raster images are accepted (no SVG/script payloads),
 *   - `avatar_path` is NOT settable through the bulk profile PATCH, and
 *   - the URL is exposed on the profile, on listings, and to admins.
 */
class AvatarTest extends TestCase
{
    private function member(string $name = 'Test Member'): User
    {
        return User::create([
            'name' => $name,
            'email' => $name.'-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    // ------------------------------------------------------------------
    // Upload / replace / remove
    // ------------------------------------------------------------------

    public function test_a_member_can_upload_a_profile_photo(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $response = $this->actingAs($member)->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('me.jpg', 10, 'image/jpeg'),
        ]);

        $response->assertOk()
            ->assertJsonPath('user.avatar_url', fn ($url) => is_string($url) && str_contains($url, 'avatars/'));

        $member->refresh();
        $this->assertNotNull($member->avatar_path);
        Storage::disk('public')->assertExists($member->avatar_path);
    }

    public function test_replacing_a_photo_deletes_the_previous_file(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('first.jpg', 10, 'image/jpeg'),
        ])->assertOk();
        $first = $member->fresh()->avatar_path;

        $this->actingAs($member)->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('second.jpg', 10, 'image/jpeg'),
        ])->assertOk();
        $second = $member->fresh()->avatar_path;

        $this->assertNotSame($first, $second);
        Storage::disk('public')->assertMissing($first);
        Storage::disk('public')->assertExists($second);
    }

    public function test_a_member_can_remove_their_photo(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('me.jpg', 10, 'image/jpeg'),
        ])->assertOk();
        $path = $member->fresh()->avatar_path;

        $this->actingAs($member)->deleteJson('/api/user/avatar')
            ->assertOk()
            ->assertJsonPath('user.avatar_url', null);

        $this->assertNull($member->fresh()->avatar_path);
        Storage::disk('public')->assertMissing($path);
    }

    public function test_removing_a_photo_that_does_not_exist_is_a_no_op(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->deleteJson('/api/user/avatar')
            ->assertOk()
            ->assertJsonPath('user.avatar_url', null);
    }

    // ------------------------------------------------------------------
    // Validation & safety
    // ------------------------------------------------------------------

    public function test_a_non_image_upload_is_rejected(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('payload.php', 10, 'application/x-php'),
        ])->assertStatus(422);

        $this->assertNull($member->fresh()->avatar_path);
    }

    public function test_the_avatar_endpoint_requires_authentication(): void
    {
        $this->post('/api/user/avatar', [
            'avatar' => UploadedFile::fake()->create('me.jpg', 10, 'image/jpeg'),
        ])->assertUnauthorized();
    }

    public function test_avatar_path_cannot_be_set_through_the_profile_patch(): void
    {
        $member = $this->member();

        // The PATCH whitelist has no avatar_path rule, so a payload carrying
        // only that key leaves nothing to update.
        $this->actingAs($member)
            ->patchJson('/api/user', ['avatar_path' => 'avatars/hacked.jpg'])
            ->assertStatus(422);

        $this->assertNull($member->fresh()->avatar_path);
    }

    // ------------------------------------------------------------------
    // Exposure to clients
    // ------------------------------------------------------------------

    public function test_avatar_url_is_exposed_on_the_profile_and_listings(): void
    {
        Storage::fake('public');
        $member = $this->member();
        $member->forceFill(['avatar_path' => 'avatars/existing.jpg'])->save();

        $this->actingAs($member)->getJson('/api/user')
            ->assertOk()
            ->assertJsonPath('avatar_url', fn ($url) => is_string($url) && str_contains($url, 'avatars/existing.jpg'));

        $marker = 'Owned by '.$member->name.' '.uniqid();
        $listing = Resource::create([
            'user_id' => $member->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => $marker,
            'description' => 'Works fine.',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);

        // Search the fixture out rather than assuming index 0: the feed ranks
        // verified residents first and paginates, so its absolute position is
        // not guaranteed.
        $rows = collect(
            $this->getJson('/api/listings?per_page=100&q='.urlencode($marker))
                ->assertOk()
                ->json('listings')
        );
        $row = $rows->firstWhere('id', $listing->id);

        $this->assertNotNull($row, 'The fixture listing must appear in the feed.');
        $this->assertIsString($row['owner']['avatar_url']);
        $this->assertStringContainsString('avatars/existing.jpg', $row['owner']['avatar_url']);
        // The owner's residency flag travels alongside the photo so the feed
        // can render a "Verified resident" badge.
        $this->assertArrayHasKey('verified', $row['owner']);
    }

    // ------------------------------------------------------------------
    // Verification documents are private (folded into this phase)
    // ------------------------------------------------------------------

    public function test_verification_documents_are_stored_on_the_private_disk(): void
    {
        Storage::fake('local');
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->post('/api/verification', [
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'document_type' => 'Barangay certificate',
            'document' => UploadedFile::fake()->create('proof.jpg', 10, 'image/jpeg'),
        ])->assertOk();

        $path = $member->fresh()->verification_document_path;
        $this->assertNotNull($path);
        Storage::disk('local')->assertExists($path);
        // The whole point of the move: the residency proof is NOT reachable at
        // a guessable public /storage/… URL.
        Storage::disk('public')->assertMissing($path);
    }
}
