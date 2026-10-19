<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Conversation;
use App\Models\Exchange;
use App\Models\MemberNotification;
use App\Models\Message;
use App\Models\Resource;
use App\Models\User;
use App\Support\BarangayLocations;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;

/**
 * The community dataset: a full board of realistic listings, every one of them
 * with photographs.
 *
 *     php artisan db:seed --class=CommunitySeeder
 *
 * This seeder REPLACES the board. It removes every listing (and the exchanges,
 * conversations and messages that hang off them) and rebuilds them from the
 * catalogue below, so the feed shows a real community rather than the debris
 * of earlier test runs. Members, categories, announcements, verification
 * records and notifications are left alone — the portal's people are not
 * disposable, only its postings are.
 *
 * The photographs are fetched separately by `tools/fetch_seed_photos.py` into
 * `storage/app/public/seed-listings/`. A listing whose photo is missing simply
 * has no photo: the seeder never points at a file that is not there.
 */
class CommunitySeeder extends Seeder
{
    /** Shared password for the demo member accounts. */
    public const DEMO_PASSWORD = 'Demo@1234';

    /** Where the seeded photographs live on the public disk. */
    private const PHOTO_DIR = 'seed-listings';

    public function run(): void
    {
        $this->purgeListings();

        $categories = $this->seedCategories();
        $members = $this->seedMembers();
        $listings = $this->seedListings($members, $categories);
        $this->seedExchanges($members, $listings);
        $this->seedConversations($members, $listings);
        $this->seedNotifications($members, $listings);

        $this->command->info('─────────────────────────────────────────────');
        $this->command->info('  Community listings ready');
        $this->command->info('  Listings      : '.count($listings));
        $this->command->info('  Members       : '.count($members));
        $this->command->info('  Demo password : '.self::DEMO_PASSWORD);
        $this->command->info('─────────────────────────────────────────────');
    }

    /**
     * Remove every listing and everything that points at one.
     *
     * `resources` carries no foreign keys (the moderation trail deliberately
     * outlives deleted rows), so nothing cascades on its own. Leaving the
     * exchanges and conversations behind would show members barter threads and
     * chats about listings that no longer exist, so they go too.
     */
    private function purgeListings(): void
    {
        $listingIds = Resource::pluck('id');

        if ($listingIds->isNotEmpty()) {
            $conversationIds = Conversation::whereIn('listing_id', $listingIds)->pluck('id');
            if ($conversationIds->isNotEmpty()) {
                Message::whereIn('conversation_id', $conversationIds)->delete();
            }
            Conversation::whereIn('listing_id', $listingIds)->delete();
        }

        // Exchanges keep their own offered_resource_id, so those are matched
        // separately before the proposals themselves are removed.
        Exchange::whereIn('resource_id', $listingIds)->delete();
        Exchange::whereIn('offered_resource_id', $listingIds)->delete();

        // The photographs of the listings that go away are not left behind.
        // The seeded photos are the exception: they belong to the catalogue
        // rather than to any one listing, and the listings below are about to
        // point at them again.
        foreach ($this->photoPathsOfEveryListing() as $path) {
            if (! str_starts_with($path, self::PHOTO_DIR.'/')) {
                Storage::disk('public')->delete($path);
            }
        }

        Resource::query()->delete();

        $this->command->info('  Removed the previous listings, exchanges and chats.');
    }

    /**
     * Every photograph path any listing currently references.
     *
     * `image_paths` is cast to an array on the model, so a plucked value can
     * already be a decoded array; a row written before the cast can still be
     * a JSON string. Both shapes are accepted here.
     *
     * @return array<int,string>
     */
    private function photoPathsOfEveryListing(): array
    {
        $paths = Resource::pluck('image_path')->filter()->all();

        foreach (Resource::pluck('image_paths')->filter() as $gallery) {
            $list = is_string($gallery) ? json_decode($gallery, true) : $gallery;
            foreach ((array) $list as $path) {
                if (is_string($path) && $path !== '') {
                    $paths[] = $path;
                }
            }
        }

        return array_values(array_unique($paths));
    }

    /** Make sure every category the catalogue uses exists. */
    private function seedCategories(): array
    {
        $names = ['Appliances', 'Electronics', 'Garden', 'Furniture', 'Education', 'Home', 'Sports', 'Tools', 'Food', 'Services'];
        $categories = [];

        foreach ($names as $name) {
            $categories[$name] = Category::firstOrCreate(['name' => $name]);
        }

        return $categories;
    }

    /**
     * The community members who own the listings.
     *
     * The first four are the original demo accounts (kept, so their existing
     * history stays coherent); the rest are new neighbours spread over the
     * barangays, half of them verified residents.
     *
     * @return array<string,User>
     */
    private function seedMembers(): array
    {
        $rows = [
            ['key' => 'maria', 'name' => 'Maria Santos', 'email' => 'maria.santos@cblrep.test', 'barangay' => 'Poblacion', 'purok' => 'Purok 3', 'verified' => true],
            ['key' => 'pedro', 'name' => 'Pedro Reyes', 'email' => 'pedro.reyes@cblrep.test', 'barangay' => 'Banlasan', 'purok' => 'Purok 2', 'verified' => true],
            ['key' => 'ana', 'name' => 'Ana Dela Cruz', 'email' => 'ana.delacruz@cblrep.test', 'barangay' => 'Bongbong', 'purok' => 'Purok 1', 'verified' => true],
            ['key' => 'jose', 'name' => 'Jose Lim', 'email' => 'jose.lim@cblrep.test', 'barangay' => 'Catoogan', 'purok' => 'Purok 4', 'verified' => false],
            ['key' => 'lorna', 'name' => 'Lorna Ignacio', 'email' => 'lorna.ignacio@cblrep.test', 'barangay' => 'Guinobatan', 'purok' => 'Purok 2', 'verified' => true],
            ['key' => 'ramon', 'name' => 'Ramon Bautista', 'email' => 'ramon.bautista@cblrep.test', 'barangay' => 'Kauswagan', 'purok' => 'Purok 5', 'verified' => false],
            ['key' => 'teresita', 'name' => 'Teresita Ayon', 'email' => 'teresita.ayon@cblrep.test', 'barangay' => 'Kinan-oan', 'purok' => 'Purok 1', 'verified' => true],
            ['key' => 'nilo', 'name' => 'Nilo Yu', 'email' => 'nilo.yu@cblrep.test', 'barangay' => 'La Union', 'purok' => 'Purok 3', 'verified' => false],
            ['key' => 'charming', 'name' => 'Charming Abad', 'email' => 'charming.abad@cblrep.test', 'barangay' => 'La Victoria', 'purok' => 'Purok 6', 'verified' => true],
            ['key' => 'wendell', 'name' => 'Wendell Tan', 'email' => 'wendell.tan@cblrep.test', 'barangay' => 'Mabuhay Cabigohan', 'purok' => 'Purok 2', 'verified' => false],
        ];

        $members = [];

        foreach ($rows as $row) {
            $members[$row['key']] = User::updateOrCreate(
                ['email' => $row['email']],
                [
                    'name' => $row['name'],
                    'password' => Hash::make(self::DEMO_PASSWORD),
                    'role' => 'user',
                    'barangay' => $row['barangay'],
                    'barangay_or_location' => $row['barangay'],
                    'purok_sitio' => $row['purok'],
                    'is_verified' => $row['verified'],
                    'verification_status' => $row['verified'] ? 'verified' : 'pending',
                    'account_status' => 'active',
                ],
            );
        }

        return $members;
    }

    /**
     * The board itself.
     *
     * Every row names the photo slug it uses, so the listing and its
     * photographs cannot drift apart. `type` is 'offer' for something on
     * offer and 'request' for something a member is looking for — the feed
     * splits the two.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Category>  $categories
     * @return array<string,Resource>
     */
    private function seedListings(array $members, array $categories): array
    {
        $rows = [
            // ── Appliances ────────────────────────────────────────────────
            ['slug' => 'rice-cooker', 'owner' => 'maria', 'category' => 'Appliances', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Rice Cooker (1.8L, barely used)', 'condition' => 'Like New',
                'description' => 'Kept my family fed through two semesters. Works perfectly, still has the original lid and steamer basket.',
                'wanted' => 'Electric fan or blender'],
            ['slug' => 'electric-fan', 'owner' => 'nilo', 'category' => 'Appliances', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Electric Fan (3-speed, 16 inch)', 'condition' => 'Good',
                'description' => 'Heavy stand fan with a strong motor. A little dusty from the storage room but it runs quietly.',
                'wanted' => 'Extension cord or LED bulb'],
            ['slug' => 'refrigerator', 'owner' => 'ramon', 'category' => 'Appliances', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Refrigerator (single door, 200L)', 'condition' => 'Good', 'price' => 4500, 'negotiable' => true,
                'description' => 'Single-door fridge in cool cream. Frost-free, no leaks, recently cleaned. Buyer picks up in Kauswagan.'],
            ['slug' => 'washing-machine', 'owner' => 'lorna', 'category' => 'Appliances', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Washing Machine (top load, twin tub)', 'condition' => 'Good',
                'description' => 'Twin-tub washer, spin cycle is strong. We are moving house so it needs a new home.',
                'wanted' => 'Baking pan or cooking pot'],

            // ── Electronics ───────────────────────────────────────────────
            ['slug' => 'bluetooth-speaker', 'owner' => 'jose', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Bluetooth Speaker (waterproof, 10h)', 'condition' => 'Like New',
                'description' => 'Pocket-size speaker that survives a sudden downpour. Around ten hours per charge, cable included.',
                'wanted' => 'Power bank'],
            ['slug' => 'old-smartphone', 'owner' => 'charming', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Android Smartphone (64GB, working)', 'condition' => 'Good',
                'description' => 'Screen is clean, no cracks. Battery lasts a full day of calls. Reset and ready for the next owner.',
                'wanted' => 'Tablet or e-reader'],
            ['slug' => 'laptop', 'owner' => 'wendell', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Laptop (i3, 4GB RAM, 500GB HDD)', 'condition' => 'Fair', 'price' => 6500, 'negotiable' => true,
                'description' => 'Honest old workhorse for schoolwork and documents. Fan runs loud under load, battery holds about two hours.',
                'wanted' => null],
            ['slug' => 'solar-lamp', 'owner' => 'teresita', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'free',
                'title' => 'Solar Lamp (3W, with USB port)', 'condition' => 'Like New',
                'description' => 'Charges during the day and lights the whole night. Has a USB socket for a phone. Free to a good home.',
                'wanted' => null],
            ['slug' => 'television', 'owner' => 'ramon', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'CRT Television (21 inch)', 'condition' => 'Fair',
                'description' => 'Old heavy television but the picture is still clear. Perfect for a small room or a Counterpart stall.',
                'wanted' => 'Electric fan or rice cooker'],
            ['slug' => 'battery-lantern', 'owner' => 'nilo', 'category' => 'Electronics', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Rechargeable Lantern (LED, 6 hours)', 'condition' => 'Good',
                'description' => 'Bright LED lantern for power cuts. One full charge lasts most of the night.',
                'wanted' => 'Solar lamp or flashlight'],

            // ── Garden & farming ──────────────────────────────────────────
            ['slug' => 'garden-tools', 'owner' => 'pedro', 'category' => 'Garden', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Garden Tools Set (rake, hoe, trowel)', 'condition' => 'Good',
                'description' => 'Complete hand-tool set for vegetable gardening. Handles are solid hardwood, nothing bent or broken.',
                'wanted' => 'Organic fertilizer or seedlings'],
            ['slug' => 'fertilizer', 'owner' => 'pedro', 'category' => 'Garden', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Organic Fertilizer (25kg sack)', 'condition' => 'Good', 'price' => 350, 'negotiable' => false,
                'description' => 'Vermicast organic fertilizer from our backyard pit. Undamaged sealed sack, ready to spread.',
                'wanted' => null],
            ['slug' => 'rice-seedlings', 'owner' => 'teresita', 'category' => 'Garden', 'type' => 'offer', 'compensation' => 'free',
                'title' => 'Rice Seedlings (bundle, for transplanting)', 'condition' => 'Good',
                'description' => 'Extra seedlings from this planting season — free to a good home. Pick up at the field in Kinan-oan.',
                'wanted' => null],
            ['slug' => 'vegetable-basket', 'owner' => 'jose', 'category' => 'Food', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Fresh Vegetables (2kg assorted)', 'condition' => 'Like New', 'price' => 150, 'negotiable' => false,
                'description' => 'Mixed seasonal vegetables harvested this morning from our plot. Kangkong, pechay, eggplant and okra.',
                'wanted' => null],
            ['slug' => 'chicken-feed', 'owner' => 'ramon', 'category' => 'Food', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Chicken Feed (25kg, layer pellets)', 'condition' => 'Good', 'price' => 1150, 'negotiable' => true,
                'description' => 'Unopened sack of layer pellets. Bought two sacks and only need one.',
                'wanted' => null],
            ['slug' => 'plant-pots', 'owner' => 'lorna', 'category' => 'Garden', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Clay Plant Pots (assorted, 8 pieces)', 'condition' => 'Good',
                'description' => 'Eight terracotta pots in mixed sizes, all drained and ready for seedlings.',
                'wanted' => 'Rice seedlings or fertilizer'],
            ['slug' => 'chicken-coop', 'owner' => 'wendell', 'category' => 'Garden', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Chicken Coop (wooden, up to 6 heads)', 'condition' => 'Good',
                'description' => 'Sturdy wooden coop with a wire run, built for the wet season. We are moving out of town.',
                'wanted' => 'Feed or fishing net'],

            // ── Food & household ──────────────────────────────────────────
            ['slug' => 'egg-tray', 'owner' => 'charming', 'category' => 'Food', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Fresh Eggs (tray of 30)', 'condition' => 'Like New', 'price' => 210, 'negotiable' => false,
                'description' => 'Collected from our own hens this morning. Collected in La Victoria.',
                'wanted' => null],
            ['slug' => 'rice-sack', 'owner' => 'maria', 'category' => 'Food', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Sack of Rice (25kg, well dried)', 'condition' => 'Good', 'price' => 1400, 'negotiable' => true,
                'description' => 'Garut rice from the harvest, well dried and sealed. Splitting a sack we cannot finish.',
                'wanted' => null],
            ['slug' => 'cooking-pot', 'owner' => 'maria', 'category' => 'Home', 'type' => 'offer', 'compensation' => 'free',
                'title' => 'Aluminum Cooking Pot (for Fiesta)', 'condition' => 'Good',
                'description' => 'Big pot that can feed a whole barangay fiesta. No dents, handles are solid. Free — we have two.',
                'wanted' => null],
            ['slug' => 'water-container', 'owner' => 'nilo', 'category' => 'Home', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Water Container (200L, clean)', 'condition' => 'Good', 'price' => 900, 'negotiable' => false,
                'description' => 'Blue HDPE container, scrubbed and disinfected. Bought two for the dry season.',
                'wanted' => null],
            ['slug' => 'broom-set', 'owner' => 'teresita', 'category' => 'Home', 'type' => 'offer', 'compensation' => 'free',
                'description' => 'Broom and Dustpan Set', 'condition' => 'Good',
                'title' => 'Broom and Dustpan Set',
                'wanted' => null],
            ['slug' => 'sewing-fabric', 'owner' => 'ana', 'category' => 'Home', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Fabric Rolls (cotton, 3 metres)', 'condition' => 'Like New',
                'description' => 'Soft cotton fabric from a bulk order — enough for a uniform or a curtain. Two colours available.',
                'wanted' => 'Sewing machine or thread'],

            // ── Furniture ──────────────────────────────────────────────────
            ['slug' => 'bamboo-table', 'owner' => 'ana', 'category' => 'Furniture', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Bamboo Coffee Table (handmade)', 'condition' => 'Like New',
                'description' => 'Locally crafted bamboo coffee table, 90cm x 50cm. A few light scuffs on the top, no cracks.',
                'wanted' => 'Two monobloc chairs'],
            ['slug' => 'wooden-chair', 'owner' => 'charming', 'category' => 'Furniture', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Wooden Chair (solid, 2 pieces)', 'condition' => 'Good',
                'description' => 'Two sturdy wooden chairs from the old house. Paint is worn but the frames are solid.',
                'wanted' => 'Table or bench'],
            ['slug' => 'school-desk', 'owner' => 'lorna', 'category' => 'Education', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'School Desk (single, with chair)', 'condition' => 'Good',
                'description' => 'Solid desk and chair set, good for a child\'s study table. Two of them available.',
                'wanted' => 'Textbooks or school bag'],

            // ── Education ──────────────────────────────────────────────────
            ['slug' => 'study-lamp', 'owner' => 'ana', 'category' => 'Education', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Study Lamp + Review Books', 'condition' => 'Good',
                'description' => 'LED study lamp with a box of senior-high review books. Perfect for a student household.',
                'wanted' => 'Scientific calculator'],
            ['slug' => 'textbooks', 'owner' => 'wendell', 'category' => 'Education', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Senior High Review Books (set of 5)', 'condition' => 'Good',
                'description' => 'Five review books covering the core subjects, a few pencil notes inside but all pages readable.',
                'wanted' => 'Desk lamp or calculator'],

            // ── Sports ─────────────────────────────────────────────────────
            ['slug' => 'bicycle', 'owner' => 'jose', 'category' => 'Sports', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Bicycle (26", 21-speed with basket)', 'condition' => 'Good',
                'description' => '21-speed bicycle with front suspension and a front basket. Needs new grips but is road-ready.',
                'wanted' => 'Android smartphone or tablet'],
            ['slug' => 'basketball', 'owner' => 'ramon', 'category' => 'Sports', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Basketball (size 7, indoor/outdoor)', 'condition' => 'Good',
                'description' => 'Proper size-7 ball that still bounces well. Bought for the court in Kauswagan.',
                'wanted' => 'Sports shoes or whistle'],
            ['slug' => 'dumbbells', 'owner' => 'teresita', 'category' => 'Sports', 'type' => 'offer', 'compensation' => 'paid',
                'title' => 'Dumbbell Set (2 x 5kg, adjustable)', 'condition' => 'Good', 'price' => 1800, 'negotiable' => true,
                'description' => 'Adjustable dumbbells with a bar and four plates each. Space is tight in the house, so these must go.',
                'wanted' => null],
            ['slug' => 'fishing-rod', 'owner' => 'nilo', 'category' => 'Sports', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Fishing Rod with Reel (medium)', 'condition' => 'Good',
                'description' => 'Medium rod with a spinning reel, ready for the esteros. Line was replaced last month.',
                'wanted' => 'Fishing net or cooler box'],

            // ── Tools & livelihood ─────────────────────────────────────────
            ['slug' => 'sewing-machine', 'owner' => 'ana', 'category' => 'Home', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Portable Sewing Machine (foot pedal)', 'condition' => 'Good',
                'description' => 'Compact electric sewing machine with foot pedal. Serviced last month, stitches neatly.',
                'wanted' => 'Sack of rice or fabric'],
            ['slug' => 'carpentry-tools', 'owner' => 'pedro', 'category' => 'Tools', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Carpentry Tool Set (hammer, chisels, plane)', 'condition' => 'Good',
                'description' => 'Everyday carpentry set, all sharpened and oiled. Sold as one lot to a single taker.',
                'wanted' => 'Cement or paint'],
            ['slug' => 'fishing-net', 'owner' => 'wendell', 'category' => 'Tools', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Fishing Net (cast net, 8 metres)', 'condition' => 'Good',
                'description' => 'Heavy cast net with lead weights, no tears. Used twice and stored dry.',
                'wanted' => 'Feed or rope'],
            ['slug' => 'water-pump', 'owner' => 'ramon', 'category' => 'Tools', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Hand Water Pump (cast iron)', 'condition' => 'Fair',
                'description' => 'Heavy cast-iron hand pump for a shallow well. Squeaks a little but pumps well.',
                'wanted' => 'Pipe fittings or cement'],
            ['slug' => 'corn-sheller', 'owner' => 'pedro', 'category' => 'Tools', 'type' => 'offer', 'compensation' => 'barter',
                'title' => 'Corn Sheller (hand operated)', 'condition' => 'Good',
                'description' => 'Hand corn sheller that takes a cob at a time. Saves hours after harvest.',
                'wanted' => 'Sack of rice or fertilizer'],

            // ── Requests — what members are looking for ────────────────────
            ['slug' => 'frying-pan', 'owner' => 'maria', 'category' => 'Home', 'type' => 'request', 'compensation' => 'barter',
                'title' => 'Looking for: Cast Iron Pan', 'condition' => 'Good',
                'description' => 'Our old pan warped and we would rather buy a proper cast-iron one. Happy to trade eggs or rice.',
                'wanted' => 'Cast iron pan or cooking pot'],
            ['slug' => 'map-and-tarpaulin', 'owner' => 'ramon', 'category' => 'Home', 'type' => 'request', 'compensation' => 'barter',
                'title' => 'Looking for: Outdoor Tarpaulin', 'condition' => 'Good',
                'description' => 'Need a sturdy tarpaulin for a small stall. Will trade chicken feed or garden tools.',
                'wanted' => 'Tarpaulin or tent'],
            ['slug' => 'sewing-scissors', 'owner' => 'teresita', 'category' => 'Home', 'type' => 'request', 'compensation' => 'barter',
                'title' => 'Looking for: Sharp Tailor Scissors', 'condition' => 'Good',
                'description' => 'My scissors are blunt. Looking for a good pair for the uniforms we make. Trade for fabric or seedlings.',
                'wanted' => 'Sharp scissors'],
        ];

        $listings = [];

        foreach ($rows as $index => $row) {
            $owner = $members[$row['owner']];
            $category = $categories[$row['category']];

            $photos = $this->photosFor($row['slug']);
            [$lat, $lng] = BarangayLocations::for($owner->barangay);

            // Spread the board over the last two weeks so the "Recent" sort
            // shows a natural order instead of one identical timestamp.
            $postedAt = now()->subDays(13 - ($index % 13))->subHours($index % 7);

            $resource = new Resource([
                'user_id' => $owner->id,
                'category_id' => $category->id,
                'type' => $row['type'],
                'compensation_type' => $row['compensation'],
                'wanted_item' => $row['compensation'] === Resource::BARTER ? ($row['wanted'] ?? null) : null,
                'price' => $row['compensation'] === Resource::PAID ? ($row['price'] ?? null) : null,
                'price_negotiable' => (bool) ($row['negotiable'] ?? false),
                'condition' => $row['condition'],
                'title' => $row['title'],
                'description' => $row['description'],
                'location' => $owner->barangay.', '.$owner->purok_sitio,
                'barangay' => $owner->barangay,
                'purok_sitio' => $owner->purok_sitio,
                // A few hundred metres of jitter so two listings in the same
                // barangay do not land on the exact same map pin.
                'latitude' => $lat + (($index % 5) - 2) * 0.0009,
                'longitude' => $lng + (($index % 7) - 3) * 0.0009,
                'is_active' => true,
                'status' => 'active',
                'image_path' => $photos[0] ?? null,
                'image_paths' => $photos === [] ? null : $photos,
            ]);

            $resource->created_at = $postedAt;
            $resource->updated_at = $postedAt;
            $resource->save();

            $listings[$row['slug']] = $resource;
        }

        return $listings;
    }

    /**
     * The photographs that exist for a listing.
     *
     * @return array<int,string>
     */
    private function photosFor(string $slug): array
    {
        $paths = [];

        foreach ([1, 2, 3] as $index) {
            $path = self::PHOTO_DIR.'/'.$slug.'-'.$index.'.jpg';
            if (Storage::disk('public')->exists($path)) {
                $paths[] = $path;
            }
        }

        return $paths;
    }

    /**
     * Barter proposals in every state of the machine.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Resource>  $listings
     */
    private function seedExchanges(array $members, array $listings): void
    {
        $rows = [
            [
                'listing' => 'rice-cooker', 'receiver' => 'pedro',
                'offered_item' => 'Electric kettle (stainless, 1.7L)', 'status' => 'pending',
            ],
            [
                'listing' => 'garden-tools', 'receiver' => 'ana',
                'offered_item' => 'Sack of organic fertilizer (25kg)', 'status' => 'accepted',
            ],
            [
                'listing' => 'bicycle', 'receiver' => 'charming',
                'offered_item' => 'Android smartphone (64GB, working)', 'status' => 'completed', 'both_confirmed' => true,
            ],
            [
                'listing' => 'study-lamp', 'receiver' => 'maria',
                'offered_item' => 'Scientific calculator (Casio FX-991)', 'status' => 'rejected',
            ],
        ];

        foreach ($rows as $row) {
            $resource = $listings[$row['listing']] ?? null;
            if (! $resource) {
                continue;
            }

            $exchange = Exchange::firstOrCreate(
                [
                    'resource_id' => $resource->id,
                    'receiver_id' => $members[$row['receiver']]->id,
                    'provider_id' => $resource->user_id,
                ],
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

            // The listing owner hears about the proposal once.
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
                'listing' => 'rice-cooker', 'buyer' => 'pedro', 'seller' => 'maria',
                'messages' => [
                    ['pedro', 'Good day, Maria! Is the rice cooker still available?'],
                    ['maria', 'Yes it is. What are you offering in return?'],
                    ['pedro', 'A stainless electric kettle, barely used.'],
                    ['maria', 'Nice — let me think about it tonight.'],
                ],
            ],
            [
                'listing' => 'garden-tools', 'buyer' => 'ana', 'seller' => 'pedro',
                'messages' => [
                    ['ana', 'Good day! I would like to trade for the garden tools.'],
                    ['pedro', 'What are you offering?'],
                    ['ana', 'A 25kg sack of organic fertilizer from our farm.'],
                    ['pedro', 'Deal — when can we meet at the barangay hall?'],
                ],
            ],
            [
                'listing' => 'bicycle', 'buyer' => 'teresita', 'seller' => 'jose',
                'messages' => [
                    ['teresita', 'Is the bicycle still available? I can bring the solar lamp.'],
                    ['jose', 'It is. The solar lamp sounds good to me.'],
                    ['teresita', 'Great — I am in Kinan-oan, but I can travel for a good bicycle.'],
                ],
            ],
        ];

        foreach ($threads as $thread) {
            $listing = $listings[$thread['listing']] ?? null;
            if (! $listing) {
                continue;
            }

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

    /**
     * A few inbox rows so the Notifications tab has something to show.
     *
     * @param  array<string,User>  $members
     * @param  array<string,Resource>  $listings
     */
    private function seedNotifications(array $members, array $listings): void
    {
        $rows = [
            [
                'user' => 'maria', 'type' => 'announcement',
                'title' => 'Barangay assembly on Saturday',
                'body' => 'The regular barangay assembly is on Saturday morning at the hall. Please bring your IDs.',
            ],
            [
                'user' => 'maria', 'type' => 'verification',
                'title' => 'Your residency verification was approved',
                'body' => 'Welcome, resident. You can now post without a limit.',
            ],
            [
                'user' => 'pedro', 'type' => 'announcement',
                'title' => 'Water interruption on Tuesday',
                'body' => 'The water supply will be off in Poblacion and Banlasan from 9am to 1pm while the line is repaired.',
            ],
            [
                'user' => 'jose', 'type' => 'listing',
                'title' => 'Your listing is live again',
                'body' => 'A moderator reviewed "'.$listings['bicycle']->title.'" and it is back on the board.',
            ],
            [
                'user' => 'ana', 'type' => 'announcement',
                'title' => 'Compost seminar at the municipal hall',
                'body' => 'A free seminar on making organic fertilizer from farm waste. Saturday, 2pm.',
            ],
        ];

        foreach ($rows as $row) {
            MemberNotification::firstOrCreate(
                ['user_id' => $members[$row['user']]->id, 'type' => $row['type'], 'title' => $row['title']],
                [
                    'body' => $row['body'],
                    'data' => null,
                    // Some are left unread on purpose, so the badge and the
                    // "mark all as read" action have something to act on.
                    'read_at' => $row['user'] === 'ana' ? now()->subDay() : null,
                ],
            );
        }
    }
}
