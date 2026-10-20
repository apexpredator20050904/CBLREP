<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Posting a NEED — the direction rules.
 *
 * An OFFER and a NEED are the same listing seen from opposite ends, so the
 * shared columns are read differently:
 *
 *   OFFER → price is the asking price, wanted_item is what the owner wants
 *            back, condition is the item's state, photos are of the item.
 *   NEED  → price is the poster's budget ceiling, wanted_item is what the
 *            poster can trade, condition is what they can accept, photos are
 *            references of the thing wanted.
 *
 * The matrix of direction × compensation has exactly one illegal cell: a
 * NEED cannot be free. "I need this, free" is not a want ad — posting a gift
 * is what an OFFER with Free is for.
 *
 * These tests pin that matrix at the API edge, plus the payload contract
 * (`price_role` and friends) that stops every client from re-deriving the
 * meaning of a shared column.
 */
class NeedPostingTest extends TestCase
{
    private function member(string $email): User
    {
        return User::create([
            'name' => 'Test Member '.uniqid(),
            'email' => $email,
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    /** Post a listing through the public API and return the response. */
    private function postListing(User $author, array $overrides = [])
    {
        return $this->actingAs($author)->postJson('/api/listings', array_merge([
            'title' => 'Rice',
            'type' => 'request',
            'listingType' => 'request',
            'description' => 'For the weekend meal.',
            'category' => 'Food',
            'condition' => 'Any',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'compensation_type' => 'barter',
        ], $overrides));
    }

    public function test_a_free_need_is_rejected(): void
    {
        $member = $this->member('need-free@example.test');

        $this->postListing($member, ['compensation_type' => 'free'])
            ->assertStatus(422)
            ->assertJsonPath('errors.compensation_type.0', 'A need cannot be free. Choose Barter or Paid.');
    }

    public function test_a_free_offer_is_still_allowed(): void
    {
        // The illegal cell is only illegal in one direction: a gift is still
        // an OFFER of something free.
        $member = $this->member('offer-free@example.test');

        $this->postListing($member, ['type' => 'offer', 'listingType' => 'offer', 'compensation_type' => 'free'])
            ->assertCreated()
            ->assertJsonPath('data.compensation_type', 'free');
    }

    public function test_a_paid_need_requires_a_budget(): void
    {
        $member = $this->member('need-paid@example.test');

        $this->postListing($member, ['compensation_type' => 'paid'])
            ->assertStatus(422)
            ->assertJsonPath('errors.price.0', 'A price is required for a paid listing.');
    }

    public function test_a_paid_need_stores_its_budget_and_is_never_negotiable(): void
    {
        $member = $this->member('need-budget@example.test');

        $this->postListing($member, [
            'compensation_type' => 'paid',
            'price' => 300,
            'price_negotiable' => true,
        ])
            ->assertCreated()
            ->assertJsonPath('data.price', 300)
            ->assertJsonPath('data.price_negotiable', false)
            ->assertJsonPath('data.price_role', 'budget');

        $this->assertDatabaseHas('resources', [
            'user_id' => $member->id,
            'price' => 300,
            'price_negotiable' => false,
        ]);
    }

    public function test_a_barter_need_keeps_the_return_side_with_the_mirrored_meaning(): void
    {
        $member = $this->member('need-barter@example.test');

        $this->postListing($member, [
            'compensation_type' => 'barter',
            'wanted_item' => '2 hours of childcare',
        ])
            ->assertCreated()
            ->assertJsonPath('data.wanted_item', '2 hours of childcare')
            ->assertJsonPath('data.wanted_item_role', 'offers_in_return');
    }

    public function test_the_payload_publishes_which_reading_applies(): void
    {
        $member = $this->member('roles@example.test');

        $this->postListing($member, [
            'compensation_type' => 'paid',
            'price' => 250,
            'quantity' => '5 kg',
        ])
            ->assertCreated()
            // A need reads every shared column from the other end.
            ->assertJsonPath('data.price_role', 'budget')
            ->assertJsonPath('data.wanted_item_role', 'offers_in_return')
            ->assertJsonPath('data.condition_role', 'acceptable_condition')
            ->assertJsonPath('data.images_role', 'reference_photos')
            ->assertJsonPath('data.quantity', '5 kg');
    }

    public function test_an_offer_keeps_its_own_reading(): void
    {
        $member = $this->member('offer-roles@example.test');

        $this->postListing($member, [
            'type' => 'offer',
            'listingType' => 'offer',
            'compensation_type' => 'paid',
            'price' => 250,
            'wanted_item' => 'A hammer',
            'quantity' => '5 kg',
        ])
            ->assertCreated()
            ->assertJsonPath('data.price_role', 'asking')
            ->assertJsonPath('data.wanted_item_role', 'wants_in_return')
            ->assertJsonPath('data.condition_role', 'item_state')
            ->assertJsonPath('data.images_role', 'item_photos')
            // Quantity belongs to a need only.
            ->assertJsonPath('data.quantity', null);
    }

    public function test_a_need_keeps_its_quantity_and_an_offer_does_not(): void
    {
        $member = $this->member('quantity@example.test');

        $this->postListing($member, ['quantity' => '2 sacks'])->assertCreated();
        $this->assertDatabaseHas('resources', ['user_id' => $member->id, 'quantity' => '2 sacks']);

        $this->postListing($member, ['type' => 'offer', 'listingType' => 'offer', 'quantity' => '2 sacks'])
            ->assertCreated();
        $this->assertDatabaseHas('resources', [
            'user_id' => $member->id,
            'type' => 'offer',
            'quantity' => null,
        ]);
    }

    public function test_the_direction_of_a_listing_cannot_be_changed_after_posting(): void
    {
        $member = $this->member('immutable@example.test');

        $id = $this->postListing($member)->assertCreated()->json('data.id');

        $this->actingAs($member)
            ->patchJson("/api/listings/{$id}", ['type' => 'offer'])
            ->assertStatus(422)
            ->assertJsonPath(
                'message',
                "A listing's direction cannot be changed after posting. Archive this one and post a new listing instead.",
            );

        $this->assertDatabaseHas('resources', ['id' => $id, 'type' => 'request']);
    }

    public function test_a_need_cannot_be_edited_into_a_free_gift(): void
    {
        $member = $this->member('edit-free@example.test');

        $id = $this->postListing($member)->assertCreated()->json('data.id');

        $this->actingAs($member)
            ->patchJson("/api/listings/{$id}", ['compensation_type' => 'free'])
            ->assertStatus(422)
            ->assertJsonPath('errors.compensation_type.0', 'A need cannot be free. Choose Barter or Paid.');
    }

    public function test_the_model_knows_which_direction_a_listing_is(): void
    {
        $member = $this->member('model@example.test');
        $category = Category::firstOrCreate(['name' => 'Food']);

        $need = Resource::create([
            'user_id' => $member->id,
            'category_id' => $category->id,
            'type' => 'request',
            'compensation_type' => 'barter',
            'title' => 'Rice',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);

        $offer = Resource::create([
            'user_id' => $member->id,
            'category_id' => $category->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => 'Rice',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);

        $this->assertTrue($need->isNeed());
        $this->assertFalse($offer->isNeed());
        $this->assertSame('budget', $need->priceRole());
        $this->assertSame('asking', $offer->priceRole());
        $this->assertSame('offers_in_return', $need->wantedItemRole());
        $this->assertSame('wants_in_return', $offer->wantedItemRole());
        $this->assertSame('acceptable_condition', $need->conditionRole());
        $this->assertSame('item_state', $offer->conditionRole());
        $this->assertSame('reference_photos', $need->imagesRole());
        $this->assertSame('item_photos', $offer->imagesRole());
    }
}
