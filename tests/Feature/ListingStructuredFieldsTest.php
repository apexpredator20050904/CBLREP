<?php

namespace Tests\Feature;

use App\Models\User;
use Tests\TestCase;

/**
 * Structured NEED quantity and urgency.
 *
 * A NEED is a shopping-list entry, so it can now say "5 kg" as a number plus a
 * unit instead of only as a sentence, and how soon it has to be met. OFFERS
 * keep the old shape: they describe one thing the member already owns, so the
 * controller clears the quantity pair and urgency for that direction.
 *
 * The legacy free-text `quantity` column is still written (composed from the
 * pair) so older APK builds and the admin console keep rendering the amount.
 */
class ListingStructuredFieldsTest extends TestCase
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
            'is_verified' => true,
        ]);
    }

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

    public function test_a_need_stores_its_structured_quantity_and_composes_the_legacy_string(): void
    {
        $member = $this->member('structured-quantity@example.test');

        $id = $this->postListing($member, [
            'quantity_value' => 5,
            'quantity_unit' => 'kg',
        ])
            ->assertCreated()
            ->assertJsonPath('data.quantity_value', 5)
            ->assertJsonPath('data.quantity_unit', 'kg')
            ->assertJsonPath('data.quantity_unit_label', 'kg')
            ->assertJsonPath('data.quantity', '5 kg')
            ->assertJsonPath('data.quantity_role', 'needed')
            ->json('data.id');

        $this->assertDatabaseHas('resources', [
            'id' => $id,
            'quantity' => '5 kg',
            'quantity_value' => 5,
            'quantity_unit' => 'kg',
        ]);
    }

    public function test_the_unit_label_is_pluralised_from_the_amount(): void
    {
        $member = $this->member('plural-unit@example.test');

        $this->postListing($member, [
            'quantity_value' => 2,
            'quantity_unit' => 'sack',
        ])
            ->assertCreated()
            ->assertJsonPath('data.quantity', '2 sacks')
            ->assertJsonPath('data.quantity_unit_label', 'sacks');

        $this->postListing($member, [
            'quantity_value' => 1,
            'quantity_unit' => 'sack',
        ])
            ->assertCreated()
            ->assertJsonPath('data.quantity', '1 sack')
            ->assertJsonPath('data.quantity_unit_label', 'sack');
    }

    public function test_quantity_value_and_unit_must_be_sent_together(): void
    {
        $member = $this->member('quantity-pair@example.test');

        $this->postListing($member, ['quantity_value' => 5])
            ->assertStatus(422)
            ->assertJsonPath('errors.quantity_unit.0', 'Choose a unit and enter a numeric quantity.');

        $this->postListing($member, ['quantity_unit' => 'kg'])
            ->assertStatus(422)
            ->assertJsonPath('errors.quantity_value.0', 'Choose a unit and enter a numeric quantity.');
    }

    public function test_an_unknown_unit_is_rejected(): void
    {
        $member = $this->member('unknown-unit@example.test');

        $this->postListing($member, [
            'quantity_value' => 5,
            'quantity_unit' => 'bucket',
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('quantity_unit');
    }

    public function test_a_need_keeps_its_urgency_but_an_offer_does_not(): void
    {
        $member = $this->member('urgency@example.test');

        $this->postListing($member, [
            'urgency' => 'urgent',
            'quantity_value' => 5,
            'quantity_unit' => 'kg',
        ])
            ->assertCreated()
            ->assertJsonPath('data.urgency', 'urgent')
            ->assertJsonPath('data.urgency_label', 'Urgent / Today');

        $this->postListing($member, [
            'type' => 'offer',
            'listingType' => 'offer',
            'urgency' => 'urgent',
            'quantity_value' => 5,
            'quantity_unit' => 'kg',
        ])
            ->assertCreated()
            ->assertJsonPath('data.urgency', null)
            ->assertJsonPath('data.urgency_label', null)
            ->assertJsonPath('data.quantity', null)
            ->assertJsonPath('data.quantity_value', null)
            ->assertJsonPath('data.quantity_unit', null);

        $this->assertDatabaseHas('resources', [
            'user_id' => $member->id,
            'type' => 'offer',
            'quantity' => null,
            'quantity_value' => null,
            'quantity_unit' => null,
            'urgency' => null,
        ]);
    }

    public function test_an_unknown_urgency_is_rejected(): void
    {
        $member = $this->member('unknown-urgency@example.test');

        $this->postListing($member, ['urgency' => 'yesterday'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('urgency');
    }

    public function test_a_need_can_be_edited_with_a_structured_quantity_and_urgency(): void
    {
        $member = $this->member('edit-structured@example.test');

        $id = $this->postListing($member)->assertCreated()->json('data.id');

        $this->actingAs($member)
            ->patchJson("/api/listings/{$id}", [
                'quantity_value' => 2.5,
                'quantity_unit' => 'bundle',
                'urgency' => 'this_week',
            ])
            ->assertOk()
            ->assertJsonPath('data.quantity_value', 2.5)
            ->assertJsonPath('data.quantity_unit', 'bundle')
            ->assertJsonPath('data.quantity', '2.5 bundles')
            ->assertJsonPath('data.urgency', 'this_week');

        $this->assertDatabaseHas('resources', [
            'id' => $id,
            'quantity' => '2.5 bundles',
            'quantity_value' => 2.5,
            'quantity_unit' => 'bundle',
            'urgency' => 'this_week',
        ]);
    }

    public function test_a_need_can_clear_its_structured_quantity_and_urgency(): void
    {
        $member = $this->member('clear-structured@example.test');

        $id = $this->postListing($member, [
            'quantity_value' => 5,
            'quantity_unit' => 'kg',
            'urgency' => 'urgent',
        ])->assertCreated()->json('data.id');

        $this->actingAs($member)
            ->patchJson("/api/listings/{$id}", [
                'quantity_value' => null,
                'quantity_unit' => null,
                'urgency' => null,
            ])
            ->assertOk()
            ->assertJsonPath('data.quantity', null)
            ->assertJsonPath('data.quantity_value', null)
            ->assertJsonPath('data.quantity_unit', null)
            ->assertJsonPath('data.urgency', null);

        $this->assertDatabaseHas('resources', [
            'id' => $id,
            'quantity' => null,
            'quantity_value' => null,
            'quantity_unit' => null,
            'urgency' => null,
        ]);
    }

    public function test_a_legacy_free_text_quantity_still_works(): void
    {
        $member = $this->member('legacy-quantity@example.test');

        $this->postListing($member, ['quantity' => 'half a kilo'])
            ->assertCreated()
            ->assertJsonPath('data.quantity', 'half a kilo')
            ->assertJsonPath('data.quantity_value', null)
            ->assertJsonPath('data.quantity_unit', null);
    }
}
