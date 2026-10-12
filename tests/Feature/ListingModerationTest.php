<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A listing owner must never be able to undo an admin moderation decision.
 *
 * `PATCH /api/listings/{id}` is member-facing, so before the fix a member
 * could send `{"status":"active"}` and revive their own flagged or removed
 * listing — the moderation endpoint in AdminPortalController was bypassable
 * by the party it was meant to constrain.
 *
 * Regression coverage for that bypass, plus the close path that members
 * legitimately own.
 */
class ListingModerationTest extends TestCase
{
    use RefreshDatabase;

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
            ->assertStatus(422);

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
            ->assertStatus(422);

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

        $this->actingAs($owner)
            ->patchJson("/api/listings/{$listing->id}", ['status' => 'closed'])
            ->assertOk();

        $fresh = $listing->fresh();
        $this->assertSame('closed', $fresh->status);
        $this->assertFalse($fresh->is_active);
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
