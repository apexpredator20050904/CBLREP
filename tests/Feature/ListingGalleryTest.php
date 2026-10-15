<?php

namespace Tests\Feature;

use App\Models\Resource;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Multi-photo listings (Phase 4).
 *
 * A used item's condition is what a buyer judges, and one photo rarely shows it.
 * These tests pin the contract the mobile app relies on:
 *   - a listing can carry an ordered gallery of photos,
 *   - the legacy single `image` field still works,
 *   - the gallery is capped so a single post cannot be a photo dump,
 *   - replacing the gallery deletes the old files (no orphan accumulation),
 *   - a legacy row with only `image_path` still reports a single-url gallery,
 *   - and the cover (`image_url`) is the first gallery image.
 *
 * Note: `UploadedFile::fake()->image()` needs GD, which this environment lacks,
 * so the fakes declare an image mime type explicitly.
 */
class ListingGalleryTest extends TestCase
{
    private function member(): User
    {
        return User::create([
            'name' => 'Gallery Member',
            'email' => 'gallery-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    /** @return array<int, UploadedFile> */
    private function photos(int $count): array
    {
        $files = [];
        for ($i = 1; $i <= $count; $i++) {
            $files[] = UploadedFile::fake()->create("photo{$i}.jpg", 10, 'image/jpeg');
        }

        return $files;
    }

    private function basePayload(): array
    {
        return [
            'title' => 'A crate of mangoes',
            'type' => 'offer',
            'compensation_type' => 'free',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ];
    }

    public function test_a_listing_accepts_an_ordered_gallery(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $response = $this->actingAs($member)->post('/api/listings', array_merge(
            $this->basePayload(),
            ['images' => $this->photos(3)],
        ));

        $response->assertCreated();
        $urls = $response->json('data.image_urls');
        $this->assertIsArray($urls);
        $this->assertCount(3, $urls);
        // The cover is the first gallery image.
        $this->assertSame($urls[0], $response->json('data.image_url'));

        $resource = Resource::where('user_id', $member->id)->firstOrFail();
        $this->assertCount(3, $resource->imagePaths());
        foreach ($resource->imagePaths() as $path) {
            Storage::disk('public')->assertExists($path);
        }
    }

    public function test_the_legacy_single_image_field_still_works(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $response = $this->actingAs($member)->post('/api/listings', array_merge(
            $this->basePayload(),
            ['image' => UploadedFile::fake()->create('only.jpg', 10, 'image/jpeg')],
        ));

        $response->assertCreated();
        $this->assertCount(1, $response->json('data.image_urls'));
        $this->assertSame($response->json('data.image_url'), $response->json('data.image_urls.0'));
    }

    public function test_the_gallery_is_capped_at_six_photos(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $this->actingAs($member)->postJson('/api/listings', array_merge(
            $this->basePayload(),
            ['images' => $this->photos(7)],
        ))->assertStatus(422)->assertJsonValidationErrors('images');
    }

    public function test_replacing_the_gallery_deletes_the_previous_files(): void
    {
        Storage::fake('public');
        $member = $this->member();

        $created = $this->actingAs($member)->post('/api/listings', array_merge(
            $this->basePayload(),
            ['images' => $this->photos(2)],
        ))->assertCreated();

        $listing = Resource::where('user_id', $member->id)->firstOrFail();
        $oldPaths = $listing->imagePaths();
        $this->assertCount(2, $oldPaths);

        $this->actingAs($member)->post("/api/listings/{$listing->id}", array_merge(
            ['_method' => 'PATCH'],
            ['images' => $this->photos(1)],
        ))->assertOk();

        $listing->refresh();
        $this->assertCount(1, $listing->imagePaths());
        foreach ($oldPaths as $path) {
            Storage::disk('public')->assertMissing($path);
        }
        Storage::disk('public')->assertExists($listing->imagePaths()[0]);
    }

    public function test_a_legacy_row_with_only_image_path_reports_one_url(): void
    {
        $member = $this->member();
        $listing = Resource::create([
            'user_id' => $member->id,
            'category_id' => \App\Models\Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'free',
            'title' => 'An old post',
            'description' => 'Before galleries existed.',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => Resource::ACTIVE,
            'image_path' => 'listing-images/legacy.jpg',
        ]);

        $payload = $listing->toFrontendListing();
        $this->assertCount(1, $payload['image_urls']);
        $this->assertSame($payload['image_url'], $payload['image_urls'][0]);
    }
}
