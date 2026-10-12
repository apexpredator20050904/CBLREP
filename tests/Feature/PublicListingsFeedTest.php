<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * The public browse feed is unauthenticated and polled by every client, so it
 * must be bounded: paginated, length-capped on search, and shaped so the
 * compensation model is unambiguous.
 *
 * These tests share the development database (see phpunit.xml) and run inside
 * a transaction that is rolled back, so every assertion is expressed relative
 * to a row baseline rather than as an absolute count.
 */
class PublicListingsFeedTest extends TestCase
{
    /** Creates $count listings owned by a single throwaway member. */
    private function seedListings(int $count): array
    {
        $owner = User::create([
            'name' => 'Seeder '.uniqid(),
            'email' => 'seeder-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
        ]);
        $categoryId = Category::firstOrCreate(['name' => 'Tools'])->id;
        $ids = [];

        for ($i = 0; $i < $count; $i++) {
            $ids[] = Resource::create([
                'user_id' => $owner->id,
                'category_id' => $categoryId,
                'type' => 'offer',
                'compensation_type' => 'barter',
                // Unique marker lets assertions target only this fixture.
                'title' => "ZZTEST{$i} ".uniqid(),
                'description' => '',
                'condition' => 'Good',
                'location' => 'Poblacion, Purok 3',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
                'is_active' => true,
                'status' => 'active',
            ])->id;
        }

        return $ids;
    }

    /** Titles this test created, which is all these assertions care about. */
    private function titlesIn(TestResponse $response): array
    {
        return array_values(array_filter(
            array_column($response->json('listings'), 'title'),
            fn ($title) => str_starts_with($title, 'ZZTEST')
        ));
    }

    public function test_the_feed_is_paginated_and_reports_meta(): void
    {
        $this->seedListings(45);

        $response = $this->getJson('/api/listings')->assertOk();

        $this->assertCount(30, $response->json('listings'), 'Default page size is 30.');
        $this->assertSame($this->baseline('resources'), $response->json('meta.total'));
        $this->assertGreaterThan(1, $response->json('meta.last_page'));
        $this->assertTrue($response->json('meta.has_more'));
    }

    public function test_per_page_is_clamped(): void
    {
        $this->getJson('/api/listings?per_page=9999')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 100);

        $this->getJson('/api/listings?per_page=0')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 1);
    }

    public function test_paging_walks_the_whole_result_set_without_repeats(): void
    {
        $ids = $this->seedListings(45);
        $before = $this->baseline('resources') - 45;

        $seen = [];
        $page = 1;
        $lastPage = null;

        do {
            $response = $this->getJson("/api/listings?page={$page}&per_page=30")->assertOk();
            $lastPage = $response->json('meta.last_page');
            foreach ($response->json('listings') as $row) {
                $seen[] = $row['id'];
            }
            $page++;
        } while ($page <= $lastPage);

        $this->assertCount(count($seen), array_unique($seen), 'No listing appears twice.');
        $this->assertEmpty(
            array_diff($ids, $seen),
            'Every created listing is reachable through the pages.'
        );
        $this->assertSame($before + 45, count($seen), 'All rows are accounted for.');
    }

    public function test_inactive_and_moderated_listings_are_excluded(): void
    {
        $ids = $this->seedListings(2);
        Resource::find($ids[0])->update(['is_active' => false]);

        $response = $this->getJson('/api/listings?per_page=100')->assertOk();
        $titles = $this->titlesIn($response);

        $this->assertCount(1, $titles, 'The deactivated fixture must not appear.');
    }

    public function test_a_flagged_listing_is_withheld_from_the_public_feed(): void
    {
        $ids = $this->seedListings(1);

        // Exactly what AdminPortalController::moderateResource writes for the
        // `flag` action: status changes AND is_active drops, which is what
        // actually gates the public feed.
        Resource::find($ids[0])->update(['status' => 'flagged', 'is_active' => false]);

        $response = $this->getJson('/api/listings?per_page=100')->assertOk();
        $returned = array_column($response->json('listings'), 'id');

        $this->assertNotContains($ids[0], $returned, 'A moderated listing is not public.');
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
        $ids = $this->seedListings(2);
        Resource::find($ids[0])->update(['barangay' => 'Tagum Norte']);

        $north = $this->getJson('/api/listings?barangay=Tagum Norte&per_page=100')->assertOk();
        $poblacion = $this->getJson('/api/listings?barangay=Poblacion&per_page=100')->assertOk();

        $northIds = array_column($this->filterToIds($north, $ids), null);
        $this->assertSame([$ids[0]], array_values($northIds));
        $this->assertSame([$ids[1]], array_values($this->filterToIds($poblacion, $ids)));
    }

    /** Narrows a feed response down to the ids this test created. */
    private function filterToIds($response, array $ids): array
    {
        $found = array_column($response->json('listings'), 'id');

        return array_values(array_intersect($ids, $found));
    }

    public function test_an_oversized_search_term_is_truncated_not_rejected(): void
    {
        $this->seedListings(2);

        // Must not error and must not pass an unbounded term to the scan.
        $response = $this->getJson('/api/listings?q='.urlencode(str_repeat('x', 500)))
            ->assertOk();

        $this->assertSame([], $this->titlesIn($response));
    }

    public function test_search_finds_a_listing_by_title(): void
    {
        $marker = 'ZZTEST'.uniqid();
        $this->seedListings(3);
        // Rename one fixture so the marker is uniquely searchable.
        $target = Resource::where('title', 'like', 'ZZTEST%')->latest()->first();
        $target->update(['title' => $marker]);

        $response = $this->getJson('/api/listings?q='.urlencode($marker))->assertOk();
        $ids = array_column($response->json('listings'), 'id');

        $this->assertContains($target->id, $ids);
    }

    public function test_the_compensation_model_is_explicit_in_the_payload(): void
    {
        $this->seedListings(1);
        $listing = Resource::where('title', 'like', 'ZZTEST%')->latest()->first();
        $listing->update(['compensation_type' => 'paid', 'price' => 250]);

        $response = $this->getJson('/api/listings?per_page=100')->assertOk();
        $row = collect($response->json('listings'))->firstWhere('id', $listing->id);

        $this->assertNotNull($row, 'The paid fixture must be in the feed.');
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

    public function test_the_public_feed_is_rate_limited(): void
    {
        // 120/min per IP. Burst past that and the limiter answers 429.
        $statuses = [];
        for ($i = 0; $i < 130; $i++) {
            $statuses[] = $this->getJson('/api/listings')->status();
        }

        $this->assertContains(429, $statuses, 'The limiter must engage.');
        $this->assertContains(200, $statuses, 'Early requests still succeed.');
    }
}
