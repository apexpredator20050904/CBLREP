<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * A listing owner must never be able to undo an admin moderation decision,
 * while still owning the ordinary lifecycle of their own listing.
 *
 * `PATCH /api/listings/{id}` is member-facing, so before the fix a member
 * could send `{"status":"active"}` and revive their own flagged or removed
 * listing — the moderation endpoint in AdminPortalController was bypassable
 * by the party it was meant to constrain.
 *
 * The rule now: an owner may move a listing between the lifecycle statuses
 * (active / paused / traded / archived) only while it is in one of them; a
 * listing a moderator has flagged/hidden/removed is frozen to the owner (403).
 *
 * Regression coverage for the bypass, the lifecycle transitions members
 * legitimately own, and the archive-instead-of-delete path.
 */
class ListingModerationTest extends TestCase
{
    private function member(): User
    {
        return User::create([
            'name' => 'Test Member',
            'email' => 'member@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    private function listingFor(User $owner): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => 'A borrowed drill',
            'description' => 'Works fine.',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    public function test_owner_cannot_reopen_a_flagged_listing(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);
        $listing->update(['status' => 'flagged', 'is_active' => false]);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'active'])
            ->assertStatus(403);

        $fresh = $listing->fresh();
        $this->assertSame('flagged', $fresh->status);
        $this->assertFalse($fresh->is_active, 'A flagged listing must stay hidden.');
    }

    public function test_owner_cannot_reopen_a_removed_listing(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);
        $listing->update(['status' => 'removed', 'is_active' => false]);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'active'])
            ->assertStatus(403);

        $fresh = $listing->fresh();
        $this->assertSame('removed', $fresh->status);
        $this->assertFalse($fresh->is_active);
    }

    public function test_editing_a_flagged_listing_does_not_change_its_visibility(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);
        $listing->update(['status' => 'flagged', 'is_active' => false]);

        // A normal content edit carries no `status` key at all.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['title' => 'A better drill'])
            ->assertOk();

        $fresh = $listing->fresh();
        $this->assertSame('A better drill', $fresh->title, 'The title edit should apply.');
        $this->assertSame('flagged', $fresh->status, 'Moderation status must survive an edit.');
        $this->assertFalse($fresh->is_active);
    }

    public function test_owner_can_still_close_their_own_listing(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);

        // "closed" is the legacy word for an archive; it is folded into the
        // canonical "archived" status on write.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'closed'])
            ->assertOk();

        $fresh = $listing->fresh();
        $this->assertSame('archived', $fresh->status);
        $this->assertFalse($fresh->is_active);
    }

    public function test_owner_can_pause_and_resume_their_own_listing(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'paused'])
            ->assertOk();
        $this->assertSame('paused', $listing->fresh()->status);
        $this->assertFalse($listing->fresh()->is_active);

        // Re-opening a paused listing is an owner decision and must succeed —
        // it is NOT a moderation state, so nothing is being bypassed.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'active'])
            ->assertOk();
        $this->assertSame('active', $listing->fresh()->status);
        $this->assertTrue($listing->fresh()->is_active);
    }

    public function test_owner_can_mark_a_listing_traded(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'traded'])
            ->assertOk();

        $this->assertSame('traded', $listing->fresh()->status);
        $this->assertFalse($listing->fresh()->is_active);
    }

    public function test_owner_cannot_pause_a_flagged_listing(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);
        $listing->update(['status' => 'hidden', 'is_active' => false]);

        // Any owner status change on a moderated listing is refused, not just
        // re-opening: the moderator's state is not the owner's to move.
        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'paused'])
            ->assertStatus(403);

        $this->assertSame('hidden', $listing->fresh()->status);
    }

    public function test_delete_archives_the_listing_and_keeps_the_row(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);

        $this->actingAs($owner)
            ->deleteJson("/api/listings/{$listing->id}")
            ->assertOk();

        $fresh = $listing->fresh();
        $this->assertNotNull($fresh, 'Archiving must not hard-delete the row.');
        $this->assertSame('archived', $fresh->status);
        $this->assertFalse($fresh->is_active);
    }

    public function test_my_listings_includes_non_active_rows(): void
    {
        $owner = $this->member();
        $active = $this->listingFor($owner);
        $paused = $this->listingFor($owner);
        $paused->applyOwnerStatus('paused');
        $paused->save();
        $archived = $this->listingFor($owner);
        $archived->applyOwnerStatus('archived');
        $archived->save();

        $response = $this->actingAs($owner)
            ->getJson('/api/my-listings')
            ->assertOk();

        $ids = collect($response->json('listings'))->pluck('id')->all();
        $this->assertContains($active->id, $ids);
        $this->assertContains($paused->id, $ids, 'A paused listing must be listed back to its owner.');
        $this->assertContains($archived->id, $ids, 'An archived listing must be listed back to its owner.');

        $this->assertSame(1, $response->json('counts.active'));
        $this->assertSame(1, $response->json('counts.paused'));
        $this->assertSame(1, $response->json('counts.archived'));
        $this->assertSame(3, $response->json('counts.all'));
    }

    public function test_my_listings_is_scoped_to_the_signed_in_member(): void
    {
        $owner = $this->member();
        $this->listingFor($owner);
        $other = User::create([
            'name' => 'Someone Else',
            'email' => 'other@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
        ]);

        $response = $this->actingAs($other)->getJson('/api/my-listings')->assertOk();

        $this->assertSame([], $response->json('listings'));
        $this->assertSame(0, $response->json('counts.all'));
    }

    public function test_owner_cannot_edit_another_members_listing(): void
    {
        $owner = $this->member();
        $intruder = User::create([
            'name' => 'Someone Else',
            'email' => 'else@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
        ]);
        $listing = $this->listingFor($owner);

        $this->actingAs($intruder)
            ->patchJson("/api/listings/{$listing->id}", ['title' => 'Hijacked'])
            ->assertNotFound();

        $this->assertSame('A borrowed drill', $listing->fresh()->title);
    }

    public function test_barter_listing_stores_what_the_owner_wants_in_return(): void
    {
        $owner = $this->member();

        $this->actingAs($owner)
            ->postJson('/api/listings', [
                'title' => 'A drill',
                'type' => 'offer',
                'compensation_type' => 'barter',
                'wanted_item' => 'A hammer',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated();

        $this->assertDatabaseHas('resources', [
            'title' => 'A drill',
            'wanted_item' => 'A hammer',
        ]);
    }

    public function test_wanted_item_is_ignored_on_non_barter_listings(): void
    {
        $owner = $this->member();

        // A free listing has no return side, so the field must not survive.
        $this->actingAs($owner)
            ->postJson('/api/listings', [
                'title' => 'A gift',
                'type' => 'offer',
                'compensation_type' => 'free',
                'wanted_item' => 'A hammer',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
            ])
            ->assertCreated();

        $this->assertDatabaseHas('resources', [
            'title' => 'A gift',
            'wanted_item' => null,
        ]);
    }

    public function test_wanted_item_can_be_updated(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['wanted_item' => 'A bicycle'])
            ->assertOk();

        $this->assertSame('A bicycle', $listing->fresh()->wanted_item);
    }

    public function test_wanted_item_is_cleared_when_compensation_leaves_barter(): void
    {
        $owner = $this->member();
        $listing = $this->listingFor($owner);
        $listing->update(['wanted_item' => 'A hammer']);

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['compensation_type' => 'free'])
            ->assertOk();

        $this->assertNull($listing->fresh()->wanted_item,
            'A gift has no return side — the stale wanted note must not survive.');
    }

    public function test_another_member_cannot_close_the_listing(): void
    {
        $owner = $this->member();
        $intruder = User::create([
            'name' => 'Someone Else',
            'email' => 'else@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
        $listing = $this->listingFor($owner);

        // The close button is gated in the UI; the backend guard is the
        // authority. Both PATCH (soft close) and DELETE (hard delete) are
        // owner-scoped, so a non-owner gets 404 — never a silent success.
        $this->actingAs($intruder)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'closed'])
            ->assertNotFound();

        $this->actingAs($intruder)
            ->deleteJson("/api/listings/{$listing->id}")
            ->assertNotFound();

        $fresh = $listing->fresh();
        $this->assertSame('active', $fresh->status);
        $this->assertTrue($fresh->is_active);
    }

    public function test_paid_listing_requires_a_price(): void
    {
        $owner = $this->member();

        $this->actingAs($owner)
            ->postJson('/api/listings', [
                'title' => 'A laptop for sale',
                'type' => 'offer',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
                'compensation_type' => 'paid',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('price');
    }

    public function test_free_listing_never_stores_a_price(): void
    {
        $owner = $this->member();

        $this->actingAs($owner)
            ->postJson('/api/listings', [
                'title' => 'Free rice sacks',
                'type' => 'offer',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 3',
                'compensation_type' => 'free',
                'price' => 500,
            ])
            ->assertCreated();

        $this->assertDatabaseHas('resources', [
            'compensation_type' => 'free',
            'price' => null,
        ]);
    }
}
