<?php

namespace Tests\Feature;

use App\Http\Middleware\AdminMiddleware;
use App\Models\Category;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * The admin console's own payloads.
 *
 * The console does not read the member-facing listing shape: it has its own
 * row builders, and a field they do not publish is a field the panel cannot
 * show. Two of those gaps were silent:
 *
 *   - a listing row carried no `price_role`, so a NEED's budget ceiling was
 *     read as an asking price, and no `quantity`, so "how much is needed"
 *     was invisible;
 *   - the listing row's `type` was "Request" while the Type filter offered
 *     "Need", so a need could never be filtered at all.
 *
 * And on the exchange table the owner was read from the fixed
 * provider/receiver mapping, so a FULFILMENT printed the same member in
 * both the proposer and the owner column.
 */
class AdminConsolePayloadTest extends TestCase
{
    /**
     * A bearer token for the ONE account the console accepts.
     *
     * The admin route group is behind AdminMiddleware, which allows only
     * `admin@cblrep.ph` and only a token minted by the 2FA flow — so the
     * test has to speak the same protocol the real console does.
     */
    private function adminToken(): string
    {
        $admin = User::firstOrCreate(
            ['email' => AdminMiddleware::SUPER_ADMIN_EMAIL],
            [
                'name' => 'Administrator',
                'password' => bcrypt('secret1234'),
                'role' => User::ROLE_SUPER_ADMIN,
                'barangay' => 'Poblacion',
                'barangay_or_location' => 'Poblacion',
            ],
        );

        return $admin->createToken(AdminMiddleware::TWO_FACTOR_TOKEN)->plainTextToken;
    }

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

    private function need(User $owner, string $title = 'Rice', string $compensation = 'barter'): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Food'])->id,
            'type' => 'request',
            'compensation_type' => $compensation,
            'price' => $compensation === 'paid' ? 300 : null,
            'wanted_item' => '2 hours of childcare',
            'quantity' => '5 kg',
            'title' => $title,
            'description' => '',
            'condition' => 'Any',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    public function test_a_listing_row_publishes_which_reading_applies(): void
    {
        $token = $this->adminToken();
        $poster = $this->member('poster@example.test');
        $this->need($poster, 'A barter need');
        $this->need($poster, 'A paid need', 'paid');

        $rows = collect($this->withToken($token)
            ->getJson('/api/admin/resources?kind=needs')
            ->assertOk()
            ->json('resources'));

        $barter = $rows->firstWhere('title', 'A barter need');
        $this->assertSame('budget', $barter['price_role']);
        $this->assertSame('offers_in_return', $barter['wanted_item_role']);
        $this->assertSame('acceptable_condition', $barter['condition_role']);
        $this->assertSame('reference_photos', $barter['images_role']);
        $this->assertSame('5 kg', $barter['quantity']);
        $this->assertSame('2 hours of childcare', $barter['wanted_item']);

        // A paid need's figure is a budget ceiling, and the panel has to be
        // able to say so.
        $paid = $rows->firstWhere('title', 'A paid need');
        $this->assertSame('budget', $paid['price_role']);
        $this->assertSame(300, $paid['price']);
        // A paid listing has no return side at all.
        $this->assertNull($paid['wanted_item']);
    }

    public function test_a_listing_row_is_labelled_the_way_the_type_filter_offers(): void
    {
        // The filter compares exactly, so the row's word has to be the word
        // the filter offers — otherwise a need can never be filtered.
        $token = $this->adminToken();
        $poster = $this->member('poster@example.test');
        $need = $this->need($poster);

        $rows = $this->withToken($token)
            ->getJson('/api/admin/resources?kind=needs')
            ->assertOk()
            ->json('resources');

        $this->assertSame('Need', $rows[0]['type']);

        $offer = Resource::create([
            'user_id' => $poster->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => 'A drill',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);

        $all = $this->withToken($token)->getJson('/api/admin/resources')->assertOk()->json('resources');
        $offerRow = collect($all)->firstWhere('id', $offer->id);
        $this->assertSame('Offer', $offerRow['type']);
    }

    public function test_an_exchange_row_names_the_two_parties_of_a_fulfilment(): void
    {
        $token = $this->adminToken();
        $poster = $this->member('poster@example.test');
        $supplier = $this->member('supplier@example.test');
        $need = $this->need($poster);

        Exchange::create([
            'resource_id' => $need->id,
            'offered_item' => '2 hours of childcare',
            'provider_id' => $supplier->id,
            'receiver_id' => $poster->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        $row = $this->withToken($token)
            ->getJson('/api/admin/exchanges')
            ->assertOk()
            ->json('exchanges.0');

        $this->assertSame('fulfilment', $row['kind']);
        // The proposer is the supplier, the owner is the poster who asked.
        $this->assertSame($supplier->name, $row['proposer_name']);
        $this->assertSame($poster->name, $row['owner_name']);
        $this->assertNotSame($row['proposer_name'], $row['owner_name']);
    }

    public function test_a_trade_row_still_names_the_owner_and_the_proposer(): void
    {
        $token = $this->adminToken();
        $owner = $this->member('owner@example.test');
        $proposer = $this->member('proposer@example.test');
        $listing = Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => 'A drill',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);

        Exchange::create([
            'resource_id' => $listing->id,
            'offered_item' => 'A hammer',
            'provider_id' => $owner->id,
            'receiver_id' => $proposer->id,
            'exchange_type' => Exchange::TYPE_BARTER,
            'status' => Exchange::STATUS_PENDING,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);

        $row = $this->withToken($token)
            ->getJson('/api/admin/exchanges')
            ->assertOk()
            ->json('exchanges.0');

        $this->assertSame('trade', $row['kind']);
        $this->assertSame($proposer->name, $row['proposer_name']);
        $this->assertSame($owner->name, $row['owner_name']);
    }
}
