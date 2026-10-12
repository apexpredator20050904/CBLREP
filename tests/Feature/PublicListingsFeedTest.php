<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The public browse feed is unauthenticated and polled by every client, so it
 * must be bounded: paginated, length-capped on search, and shaped so the
 * compensation model is unambiguous.
 */
class PublicListingsFeedTest extends TestCase
{
    use RefreshDatabase;

    private function seedListings(int $count): void
    {
        $owner = User::create([
            'name' => 'Seeder',
            'email' => 'seeder@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
        ]);
        $categoryId = Category::firstOrCreate(['name' => 'Tools'])->id;

        for ($i = 0; $i < $count; $i++) {
            Resource::create([
                'user_id' => $owner->id,
                'category_id' => $categoryId,
                'type' => 'offer',
                'compensation_type' => 'barter',
                'title' => "Listing {$i}",
                'description' => '',
                'condition' => 'Good',
                'location' => 'Poblacion, Purok 3',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
                'is_active' => true,
                'status' => 'active',
            ]);
        }
    }

    public function test_the_feed_is_paginated_and_reports_meta(): void
    {
        $this->seedListings(45);

        $response = $this->getJson('/api/listings')->assertOk();

        $this->assertCount(30, $response->json('listings'), 'Default page size is 30.');
        $this->assertSame(45, $response->json('meta.total'));
        $this->assertSame(2, $response->json('meta.last_page'));
        $this->assertTrue($response->json('meta.has_more'));
    }

    public function test_per_page_is_clamped(): void
    {
        $this->seedListings(5);

        $this->getJson('/api/listings?per_page=9999')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 100);

        $this->getJson('/api/listings?per_page=0')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 1);
    }

    public function test_page_two_returns_the_remainder(): void
    {
        $this->seedListings(45);

        $response = $this->getJson('/api/listings?page=2&per_page=30')->assertOk();

        $this->assertCount(15, $response->json('listings'));
        $this->assertSame(2, $response->json('meta.current_page'));
        $this->assertFalse($response->json('meta.has_more'));
    }

    public function test_inactive_and_moderated_listings_are_excluded(): void
    {
        $this->seedListings(2);
        $hidden = Resource::first();
        $hidden->update(['is_active' => false]);

        $response = $this->getJson('/api/listings')->assertOk();
        $this->assertCount(1, $response->json('listings'));
    }

    public function test_the_legacy_data_alias_is_still_present(): void
    {
        // Older mobile builds read `data` instead of `listings`.
        $this->seedListings(3);

        $response = $this->getJson('/api/listings')->assertOk();
        $this->assertSame(
            $response->json('listings'),
            $response->json('data'),
            '`data` must remain an alias of `listings` for existing clients.',
        );
    }

    public function test_barangay_filter_narrows_the_feed(): void
    {
        $this->seedListings(2);
        $other = Resource::first();
        $other->update(['barangay' => 'Tagum Norte']);

        $this->getJson('/api/listings?barangay=Tagum Norte')
            ->assertOk()
            ->assertJsonCount(1, 'listings');

        $this->getJson('/api/listings?barangay=Poblacion')
            ->assertOk()
            ->assertJsonCount(1, 'listings');
    }

    public function test_an_oversized_search_term_is_truncated_not_rejected(): void
    {
        $this->seedListings(2);

        // Must not error and must not pass an unbounded term to the scan.
        $this->getJson('/api/listings?q='.urlencode(str_repeat('x', 500)))
            ->assertOk()
            ->assertJsonCount(0, 'listings');
    }

    public function test_the_compensation_model_is_explicit_in_the_payload(): void
    {
        $this->seedListings(1);
        $listing = Resource::first();
        $listing->update(['compensation_type' => 'paid', 'price' => 250]);

        $row = $this->getJson('/api/listings')->assertOk()->json('listings.0');

        $this->assertSame('paid', $row['compensation_type']);
        $this->assertSame('PAID', $row['compensation_label']);
        $this->assertEquals(250, $row['price']);
        $this->assertSame('Poblacion', $row['barangay']);
        $this->assertSame('Purok 3', $row['purok_sitio']);
    }

    public function test_the_removed_presence_endpoint_is_gone(): void
    {
        $this->getJson('/api/presence')->assertNotFound();
        $this->postJson('/api/presence', ['email' => 'x@example.test'])->assertNotFound();
    }
}
