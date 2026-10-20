<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\ContentPage;
use App\Models\Conversation;
use App\Models\Exchange;
use App\Models\MemberNotification;
use App\Models\Message;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Defense demonstration data.
 *
 * DatabaseSeeder is destructive by design — it TRUNCATEs every domain table
 * and leaves only the Super Admin, so running it on the live database wipes
 * real rows. This seeder is the opposite: it is additive and idempotent.
 * Every row is created with firstOrCreate/updateOrCreate keyed on a natural
 * identity, so it can be run any number of times and will never delete or
 * duplicate existing data.
 *
 *     php artisan db:seed --class=DemoSeeder
 *
 * It produces a realistic, defensible dataset for the panel:
 *   - 4 member accounts (all sharing {@see DEMO_PASSWORD})
 *   - a category set
 *   - barter / free / paid listings across real Trinidad barangays
 *   - barter proposals in every state of the machine
 *     (pending, accepted, completed, rejected)
 *   - listing-scoped conversations with a message history
 *   - member notifications for the proposals
 *
 * Existing data (including any accounts a classmate already registered) is
 * left completely untouched.
 */
class DemoSeeder extends Seeder
{
    /** Shared password for every demo member account. */
    public const DEMO_PASSWORD = 'Demo@1234';

    public function run(): void
    {
        $categories = $this->seedCategories();
        $members = $this->seedMembers();
        $listings = $this->seedListings($members, $categories);
        $this->seedExchanges($members, $listings);
        $this->seedConversations($members, $listings);
        $this->seedExampleContentPage();

        $this->command->info('─────────────────────────────────────────────');
        $this->command->info('  Demo data ready (non-destructive)');
        $this->command->info('  Member password: '.self::DEMO_PASSWORD);
        $this->command->info('  Accounts:');
        foreach ($members as $member) {
            $this->command->info("    {$member->email}  ({$member->barangay})");
        }
        $this->command->info('─────────────────────────────────────────────');
    }

    /**
     * Example public content page (idempotent — safe to re-run).
     *
     * Reachable anonymously at GET /api/page/waste-segregation-guide and, via
     * the React public route, at /page/waste-segregation-guide — the smoke
     * test for the public content-page feature.
     */
    private function seedExampleContentPage(): void
    {
        $adminId = User::query()->orderBy('id')->value('id');

        ContentPage::firstOrCreate(
            ['slug' => 'waste-segregation-guide'],
            [
                'title' => 'Waste Segregation Guide',
                'body' => '<h2>Waste Segregation Guide</h2>'
                    . '<p>Trinidad barangays sort household waste into three bins:</p>'
                    . '<ul>'
                    . '<li><strong>Green bin</strong> — organic waste (fruit peels, coffee grounds, garden trimmings).</li>'
                    . '<li><strong>Blue bin</strong> — recyclables (plastic bottles, glass jars, steel cans, newspapers).</li>'
                    . '<li><strong>Black bin</strong> — general refuse.</li>'
                    . '</ul>'
                    . '<p>Rinse all recyclables before binning and keep them dry.</p>',
                'status' => 'published',
                'created_by' => $adminId,
                'published_at' => now()->subDay(),
            ]
        );

        $this->command->info('  Public example page: /page/waste-segregation-guide');
    }

    /** @return array<string,Category> keyed by name */
    private function seedCategories(): array
    {
        $names = [
            'Appliances', 'Electronics', 'Furniture', 'Garden',
            'Tools', 'Sports', 'Education', 'Home', 'Food',
        ];

        $categories = [];
        foreach ($names as $name) {
            $categories[$name] = Category::firstOrCreate(['name' => $name]);
        }

        return $categories;
    }

    /**
     * Create (or refresh) the demo member accounts.
     *
     * Emails use the reserved `.test` TLD so they can never collide with a
     * real member's address. The password is written in plaintext and hashed
     * by the `password` cast on the User model.
     *
     * @return array<string,User> keyed by a short handle
     */
    private function seedMembers(): array
    {
        $people = [
            'maria' => [
                'name' => 'Maria Santos',
                'email' => 'maria.santos@cblrep.test',
                'barangay' => 'Poblacion',
                'purok_sitio' => 'Purok 1',
                'is_verified' => true,
                'verification_status' => 'verified',
            ],
            'pedro' => [
                'name' => 'Pedro Reyes',
                'email' => 'pedro.reyes@cblrep.test',
                'barangay' => 'Banlasan',
                'purok_sitio' => 'Sitio Malinao',
                'is_verified' => true,
                'verification_status' => 'verified',
            ],
            'ana' => [
                'name' => 'Ana Dela Cruz',
                'email' => 'ana.delacruz@cblrep.test',
                'barangay' => 'Bongbong',
                'purok_sitio' => 'Purok 3',
                'is_verified' => true,
                'verification_status' => 'verified',
            ],
            'jose' => [
                'name' => 'Jose Lim',
                'email' => 'jose.lim@cblrep.test',
                'barangay' => 'Catoogan',
                'purok_sitio' => 'Purok 5',
                'is_verified' => false,
                'verification_status' => 'pending',
            ],
        ];

        $members = [];
        foreach ($people as $handle => $attrs) {
            $members[$handle] = User::updateOrCreate(
                ['email' => $attrs['email']],
                $attrs + [
                    'password' => self::DEMO_PASSWORD,
                    'role' => User::ROLE_USER,
                    'account_status' => 'active',
                    'barangay_or_location' => $attrs['barangay'],
                ],
            );
        }

        return $members;
    }

    /**
     * Create listings. `user_id + title` is the idempotency key.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Category>  $categories
     * @return array<string,Resource> keyed by a short slug
     */
    private function seedListings(array $members, array $categories): array
    {
        $rows = [
            [
                'slug' => 'rice_cooker', 'owner' => 'maria', 'category' => 'Appliances',
                'title' => 'Rice Cooker (1.8L, good condition)',
                'description' => 'Barely used 1.8L rice cooker. Kept my family fed through two semesters — still works perfectly.',
                'compensation' => 'barter', 'wanted' => 'Electric fan or blender',
            ],
            [
                'slug' => 'mountain_bike', 'owner' => 'maria', 'category' => 'Sports',
                'title' => 'Mountain Bike (26", 21-speed)',
                'description' => '21-speed mountain bike with front suspension. Needs new grips but otherwise road-ready.',
                'compensation' => 'barter', 'wanted' => 'Android smartphone or tablet',
            ],
            [
                'slug' => 'garden_tools', 'owner' => 'pedro', 'category' => 'Garden',
                'title' => 'Garden Tools Set (rake, hoe, trowel)',
                'description' => 'Complete hand-tool set for vegetable gardening. Handles are solid hardwood.',
                'compensation' => 'barter', 'wanted' => 'Organic fertilizer or seedlings',
            ],
            [
                'slug' => 'coffee_table', 'owner' => 'pedro', 'category' => 'Furniture',
                'title' => 'Handmade Bamboo Coffee Table',
                'description' => 'Locally crafted bamboo coffee table, 90cm x 50cm. A few scuffs on the top.',
                'compensation' => 'barter', 'wanted' => 'Two monobloc chairs',
            ],
            [
                'slug' => 'study_lamp', 'owner' => 'ana', 'category' => 'Education',
                'title' => 'Study Lamp + Review Books',
                'description' => 'LED study lamp with a box of senior-high review books. Perfect for a student household.',
                'compensation' => 'barter', 'wanted' => 'Scientific calculator',
            ],
            [
                'slug' => 'sewing_machine', 'owner' => 'ana', 'category' => 'Home',
                'title' => 'Portable Sewing Machine',
                'description' => 'Compact electric sewing machine with foot pedal. Serviced last month.',
                'compensation' => 'barter', 'wanted' => 'Sack of rice',
            ],
            [
                'slug' => 'bluetooth_speaker', 'owner' => 'jose', 'category' => 'Electronics',
                'title' => 'Bluetooth Speaker (waterproof)',
                'description' => 'Waterproof portable speaker, ~8 hours of playback. Charging cable included.',
                'compensation' => 'barter', 'wanted' => 'Power bank',
            ],
            [
                'slug' => 'fertilizer', 'owner' => 'pedro', 'category' => 'Garden',
                'title' => 'Bag of Organic Fertilizer (25kg)',
                'description' => 'Vermicast organic fertilizer from our backyard pit. Undamaged sealed sack.',
                'compensation' => 'barter', 'wanted' => 'Vegetable seeds or hand tools',
            ],
            // Variety: a gift and a priced sale so the panel sees all three modes.
            [
                'slug' => 'seedlings', 'owner' => 'ana', 'category' => 'Garden',
                'title' => 'Free Rice Seedlings (giveaway)',
                'description' => 'Extra rice seedlings from this planting season — free to a good home.',
                'compensation' => 'free', 'wanted' => null,
            ],
            [
                'slug' => 'vegetables', 'owner' => 'jose', 'category' => 'Garden',
                'title' => 'Fresh Vegetables Pack (2kg)',
                'description' => 'Mixed seasonal vegetables harvested this morning from our plot.',
                'compensation' => 'paid', 'wanted' => null, 'price' => 150.00,
            ],
            // ── NEEDS ────────────────────────────────────────────────────
            // A need is the same listing read from the other end: the price
            // is a budget ceiling, the wanted item is what the POSTER can
            // trade, and the quantity is how much is wanted. Seeding one of
            // each shape so a fresh install shows the whole matrix.
            [
                'slug' => 'need_rice_sack', 'owner' => 'maria', 'category' => 'Food',
                'type' => 'request',
                'title' => 'Looking for: Extra Rice Sack',
                'description' => 'Our neighbours shared a sack last planting season and we would like to do the same. Can trade eggs or a couple of hours of childcare.',
                'compensation' => 'barter', 'wanted' => 'One tray of eggs, or 2 hours of childcare',
                'quantity' => '1 sack (25 kg)', 'condition' => 'Any',
            ],
            [
                'slug' => 'need_cooking_pot', 'owner' => 'ana', 'category' => 'Home',
                'type' => 'request',
                'title' => 'Looking for: Big Cooking Pot',
                'description' => 'Something big enough to cook for a whole barangay gathering. Budget is firm, but we can pick it up today.',
                'compensation' => 'paid', 'wanted' => null, 'price' => 300.00,
                'quantity' => '1 large pot', 'condition' => 'Working',
            ],
            [
                // The no-strings case: the poster named no return side, so a
                // neighbour may bring it and ask for nothing back.
                'slug' => 'need_study_lamp', 'owner' => 'jose', 'category' => 'Electronics',
                'type' => 'request',
                'title' => 'Looking for: Working Study Lamp',
                'description' => 'Any working lamp for the night shift. No strings attached — we will take whatever you can spare.',
                'compensation' => 'barter', 'wanted' => null,
                'quantity' => '1 lamp', 'condition' => 'Any',
            ],
        ];

        $listings = [];
        foreach ($rows as $row) {
            $owner = $members[$row['owner']];
            $category = $categories[$row['category']];
            $type = $row['type'] ?? 'offer';

            $listings[$row['slug']] = Resource::firstOrCreate(
                ['user_id' => $owner->id, 'title' => $row['title']],
                [
                    'category_id' => $category->id,
                    'type' => $type,
                    'compensation_type' => $row['compensation'],
                    'wanted_item' => $row['compensation'] === Resource::BARTER ? $row['wanted'] : null,
                    'price' => $row['compensation'] === Resource::PAID ? ($row['price'] ?? null) : null,
                    // How much is needed — a need-only field.
                    'quantity' => $type === 'request' ? ($row['quantity'] ?? null) : null,
                    // On an offer the condition is the item's state; on a need
                    // it is what the poster can accept.
                    'condition' => $row['condition'] ?? 'Good',
                    'description' => $row['description'],
                    'location' => $owner->barangay.', '.$owner->purok_sitio,
                    'barangay' => $owner->barangay,
                    'purok_sitio' => $owner->purok_sitio,
                    'is_active' => true,
                    'status' => 'active',
                ],
            );
        }

        return $listings;
    }

    /**
     * Barter proposals exercising every reachable state.
     *
     * provider = owner of the wanted listing, receiver = the proposer. The
     * two-sided `offered_item` (what the proposer gives) is what keeps a
     * one-sided gift impossible.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Resource>  $listings
     */
    private function seedExchanges(array $members, array $listings): void
    {
        $rows = [
            [
                'key' => ['resource_id' => $listings['rice_cooker']->id, 'receiver_id' => $members['pedro']->id],
                'offered_item' => 'Electric kettle (stainless, 1.7L)',
                'status' => 'pending',
            ],
            [
                'key' => ['resource_id' => $listings['garden_tools']->id, 'receiver_id' => $members['ana']->id],
                'offered_item' => 'Sack of organic fertilizer (25kg)',
                'status' => 'accepted',
            ],
            [
                'key' => ['resource_id' => $listings['mountain_bike']->id, 'receiver_id' => $members['jose']->id],
                'offered_item' => 'Android smartphone (4G, 64GB)',
                'status' => 'completed',
                'both_confirmed' => true,
            ],
            [
                'key' => ['resource_id' => $listings['study_lamp']->id, 'receiver_id' => $members['maria']->id],
                'offered_item' => 'Scientific calculator (Casio FX-991)',
                'status' => 'rejected',
            ],
        ];

        foreach ($rows as $row) {
            $resource = Resource::find($row['key']['resource_id']);
            if (! $resource) {
                continue;
            }

            $exchange = Exchange::firstOrCreate(
                $row['key'] + ['provider_id' => $resource->user_id],
                [
                    'offered_item' => $row['offered_item'],
                    'exchange_type' => Exchange::TYPE_BARTER,
                    'status' => $row['status'],
                    'barangay' => $resource->barangay,
                    'purok_sitio' => $resource->purok_sitio,
                    'proposer_confirmed' => ! empty($row['both_confirmed']),
                    'owner_confirmed' => ! empty($row['both_confirmed']),
                    'proposer_confirmed_at' => ! empty($row['both_confirmed']) ? now() : null,
                    'owner_confirmed_at' => ! empty($row['both_confirmed']) ? now() : null,
                ],
            );

            // Notify the listing owner once per exchange.
            MemberNotification::firstOrCreate(
                [
                    'user_id' => $resource->user_id,
                    'type' => 'barter_proposal',
                    'data->exchange_id' => $exchange->id,
                ],
                [
                    'title' => 'New barter proposal',
                    'body' => $exchange->receiver->name.' offered to trade "'.$row['offered_item'].'" for "'.$resource->title.'".',
                    'data' => ['exchange_id' => $exchange->id, 'resource_id' => $resource->id],
                ],
            );
        }
    }

    /**
     * Listing-scoped conversations with a short, realistic message history.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Resource>  $listings
     */
    private function seedConversations(array $members, array $listings): void
    {
        $threads = [
            [
                'listing' => 'rice_cooker', 'buyer' => 'pedro', 'seller' => 'maria',
                'messages' => [
                    ['pedro', 'Hi Maria! Is the rice cooker still available?'],
                    ['maria', 'Yes it is. What are you offering in return?'],
                    ['pedro', 'A stainless electric kettle, barely used.'],
                    ['maria', 'Nice — let me think about it tonight.'],
                ],
            ],
            [
                'listing' => 'garden_tools', 'buyer' => 'ana', 'seller' => 'pedro',
                'messages' => [
                    ['ana', 'Good day! I would like to trade for the garden tools.'],
                    ['pedro', 'What are you offering?'],
                    ['ana', 'A 25kg sack of organic fertilizer from our farm.'],
                    ['pedro', 'Deal — when can we meet at the barangay hall?'],
                ],
            ],
            [
                'listing' => 'study_lamp', 'buyer' => 'maria', 'seller' => 'ana',
                'messages' => [
                    ['maria', 'Are the review books included with the lamp?'],
                    ['ana', 'Yes, all of them. What is your offer?'],
                    ['maria', 'A Casio scientific calculator.'],
                    ['ana', 'Sorry, I already have one. Maybe something else next time.'],
                ],
            ],
        ];

        foreach ($threads as $thread) {
            $listing = $listings[$thread['listing']];
            $buyer = $members[$thread['buyer']];
            $seller = $members[$thread['seller']];

            $conversation = Conversation::forListing($listing->id, $buyer->id, $seller->id);

            if ($conversation->messages()->exists()) {
                continue;
            }

            $when = now()->subDays(2);
            foreach ($thread['messages'] as [$sender, $body]) {
                $senderId = $members[$sender]->id;
                Message::create([
                    'conversation_id' => $conversation->id,
                    'sender_id' => $senderId,
                    'recipient_email' => $senderId === $buyer->id ? $seller->email : $buyer->email,
                    'body' => $body,
                    'read_at' => $when->copy()->addMinutes(5),
                    'created_at' => $when,
                    'updated_at' => $when,
                ]);
                $when = $when->copy()->addMinutes(7);
            }

            $conversation->update(['last_message_at' => $when]);
        }
    }
}
