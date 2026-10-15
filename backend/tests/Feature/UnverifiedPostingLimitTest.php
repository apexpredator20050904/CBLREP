<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Progressive trust: an unverified member may keep only a few listings live at
 * once, and completing residency verification lifts the cap.
 *
 * The cap is deliberately soft — browsing, chat, the map and trade proposals
 * stay open to everyone — so these tests also pin the escape hatches: pausing,
 * trading or archiving a listing frees a slot, and a moderator's hold never
 * counts against the member.
 */
class UnverifiedPostingLimitTest extends TestCase
{
    private function member(array $attributes = []): User
    {
        return User::create(array_merge([
            'name' => 'Test Member '.uniqid(),
            'email' => 'member-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Bongbong',
            'barangay_or_location' => 'Bongbong',
            'purok_sitio' => 'Purok 3',
        ], $attributes));
    }

    private function listingFor(User $owner, string $status = Resource::ACTIVE): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => Resource::BARTER,
            'title' => 'A listing '.uniqid(),
            'condition' => 'Good',
            'location' => 'Bongbong, Purok 3',
            'barangay' => 'Bongbong',
            'purok_sitio' => 'Purok 3',
            'is_active' => $status === Resource::ACTIVE,
            'status' => $status,
        ]);
    }

    private function postListing(User $owner)
    {
        return $this->actingAs($owner)->postJson('/api/listings', [
            'title' => 'A new listing',
            'type' => 'offer',
            'compensation_type' => 'barter',
            'barangay' => 'Bongbong',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    public function test_unverified_member_below_the_cap_can_post(): void
    {
        $owner = $this->member();
        $this->listingFor($owner);
        $this->listingFor($owner);

        $this->postListing($owner)->assertCreated();
    }

    public function test_unverified_member_at_the_cap_is_blocked(): void
    {
        $owner = $this->member();
        for ($i = 0; $i < Resource::UNVERIFIED_ACTIVE_LIMIT; $i++) {
            $this->listingFor($owner);
        }
        $before = Resource::where('user_id', $owner->id)->count();

        $this->postListing($owner)
            ->assertStatus(403)
            ->assertJsonPath('verification_required', true)
            ->assertJsonPath('active_listings_limit', Resource::UNVERIFIED_ACTIVE_LIMIT);

        $this->assertSame(
            $before,
            Resource::where('user_id', $owner->id)->count(),
            'A capped post must not create a listing.'
        );
    }

    public function test_verified_member_is_never_capped(): void
    {
        $owner = $this->member([
            'is_verified' => true,
            'verification_status' => 'verified',
        ]);
        for ($i = 0; $i < Resource::UNVERIFIED_ACTIVE_LIMIT + 2; $i++) {
            $this->listingFor($owner);
        }

        $this->postListing($owner)->assertCreated();
    }

    public function test_paused_traded_and_archived_listings_free_a_slot(): void
    {
        $owner = $this->member();
        // Two live listings plus a full spread of non-active ones: only the
        // live pair may count, so a third post stays allowed.
        $this->listingFor($owner);
        $this->listingFor($owner);
        $this->listingFor($owner, Resource::PAUSED);
        $this->listingFor($owner, Resource::TRADED);
        $this->listingFor($owner, Resource::ARCHIVED);

        $this->postListing($owner)->assertCreated();
    }

    public function test_a_moderators_hold_does_not_count_against_the_member(): void
    {
        $owner = $this->member();
        $this->listingFor($owner);
        $this->listingFor($owner);
        $this->listingFor($owner, Resource::FLAGGED);
        $this->listingFor($owner, Resource::HIDDEN);

        // Two visible rows, well under the cap, even though the member owns four.
        $this->postListing($owner)->assertCreated();
    }

    public function test_reactivating_a_listing_cannot_bypass_the_cap(): void
    {
        $owner = $this->member();
        for ($i = 0; $i < Resource::UNVERIFIED_ACTIVE_LIMIT; $i++) {
            $this->listingFor($owner);
        }
        $archived = $this->listingFor($owner, Resource::ARCHIVED);

        // Archiving frees a slot, but restoring it must not silently create a
        // fourth live listing for an unverified member.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$archived->id}", ['status' => 'active'])
            ->assertStatus(403)
            ->assertJsonPath('verification_required', true);

        $this->assertSame(Resource::ARCHIVED, $archived->fresh()->status);
    }

    public function test_reactivating_a_listing_below_the_cap_is_allowed(): void
    {
        $owner = $this->member();
        $this->listingFor($owner);
        $this->listingFor($owner);
        $paused = $this->listingFor($owner, Resource::PAUSED);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$paused->id}", ['status' => 'active'])
            ->assertOk();

        $this->assertSame(Resource::ACTIVE, $paused->fresh()->status);
    }

    public function test_editing_an_already_live_listing_is_never_capped(): void
    {
        $owner = $this->member();
        $listings = [];
        for ($i = 0; $i < Resource::UNVERIFIED_ACTIVE_LIMIT; $i++) {
            $listings[] = $this->listingFor($owner);
        }
        $first = $listings[0];

        // Re-sending `status: active` on a listing that is already live is not
        // a reactivation, so the cap must not suddenly reject an ordinary edit.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$first->id}", ['status' => 'active', 'title' => 'Renamed'])
            ->assertOk();

        $this->assertSame('Renamed', $first->fresh()->title);
    }

    public function test_mine_advertises_the_limit_to_unverified_members(): void
    {
        $owner = $this->member();
        $this->listingFor($owner);
        $this->listingFor($owner);

        $this->actingAs($owner)
            ->getJson('/api/my-listings')
            ->assertOk()
            ->assertJsonPath('limits.verified', false)
            ->assertJsonPath('limits.active_used', 2)
            ->assertJsonPath('limits.active_max', Resource::UNVERIFIED_ACTIVE_LIMIT);
    }

    public function test_mine_reports_unlimited_for_verified_members(): void
    {
        $owner = $this->member([
            'is_verified' => true,
            'verification_status' => 'verified',
        ]);

        $this->actingAs($owner)
            ->getJson('/api/my-listings')
            ->assertOk()
            ->assertJsonPath('limits.verified', true)
            ->assertJsonPath('limits.active_max', null);
    }
}
