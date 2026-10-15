<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ListingController extends Controller
{
    /// Public browse feed.
    ///
    /// Paginated with a bounded default: this endpoint is unauthenticated and
    /// the mobile client polls it, so returning every active listing on each
    /// request was both a scaling risk and an easy abuse target. Clients
    /// transparently ignore `meta` and keep reading `listings`, so the wire
    /// contract is unchanged for existing builds.
    public function index(Request $request)
    {
        $query = Resource::with(['user', 'category'])
            // The feed's visibility rule (active AND not moderated) lives on the
            // model so this query and the tests that assert against it cannot
            // drift apart.
            ->publiclyVisible()
            // Verification payoff: a verified resident's listings rank first,
            // so completing residency verification buys visibility. The
            // correlated subquery reads the owner's flag without a join, which
            // would otherwise make the scope's unqualified columns ambiguous.
            // Newest-first is the within-group order; id is the final tiebreaker
            // so pagination stays stable when created_at collides.
            ->orderByDesc(
                User::select('is_verified')->whereColumn('users.id', 'resources.user_id')
            )
            ->latest()
            ->orderByDesc('id');

        if ($barangay = trim((string) $request->query('barangay', ''))) {
            $query->where('barangay', $barangay);
        }
        if ($q = trim((string) $request->query('q', ''))) {
            // Length-capped: an unbounded search term is a wider full scan and
            // the field is a LIKE across several columns either way.
            $q = mb_substr($q, 0, 80);
            $query->where(fn ($w) => $w
                ->where('title', 'like', "%{$q}%")
                ->orWhere('description', 'like', "%{$q}%")
                ->orWhere('location', 'like', "%{$q}%")
                ->orWhere('purok_sitio', 'like', "%{$q}%"));
        }

        $perPage = min(max((int) $request->query('per_page', 30), 1), 100);
        $paginator = $query->paginate($perPage)->withQueryString();

        $listings = $paginator->getCollection()
            ->map(fn (Resource $resource) => $resource->toFrontendListing())
            ->values();

        return response()->json([
            'listings' => $listings,
            // `data` is a legacy alias kept so older mobile builds that read
            // this key keep working against a paginated response.
            'data' => $listings,
            'meta' => [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'has_more' => $paginator->hasMorePages(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'category' => 'nullable|string|max:255',
            'listingType' => 'nullable|string',
            'type' => 'nullable|string',
            // free | barter | paid — how the member wants to share.
            'compensation_type' => 'nullable|in:free,barter,paid',
            // What the owner wants back. Only meaningful for a barter — free
            // and paid listings have no return side, so it is nulled below.
            'wanted_item' => 'nullable|string|max:160',
            // Optional even for a paid sale: a seller may prefer to negotiate
            // the figure in chat, so no price is mandatory at post time.
            'price' => 'nullable|numeric|min:0|max:9999999',
            // Whether a paid seller welcomes a counter-offer. Ignored (stored
            // false) for free/barter, which have no price to negotiate.
            'price_negotiable' => 'nullable|boolean',
            'condition' => 'nullable|string|max:255',
            'location' => 'nullable|string|max:255',
            'barangay' => ['required', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['required', 'string', 'max:60', \App\Support\Puroks::rule()],
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
            // Multi-photo gallery. Kept alongside the single `image` field,
            // which older app builds still send.
            'images' => 'nullable|array|max:6',
            'images.*' => 'image|mimes:jpg,jpeg,png|max:5120',
        ]);

        // Progressive trust: an unverified member may keep only a handful of
        // listings live at once; verified residents post without limit.
        // Enforced here and on reactivation (see update) rather than as a hard
        // gate so browsing, chat and the map remain open to everyone —
        // verification buys headroom, not access. Counted against publicly
        // visible rows only, so pausing/trading/archiving frees a slot and a
        // moderator's hold cannot lock a member out of posting for good.
        if ($rejection = $this->unverifiedCapRejection($request)) {
            return $rejection;
        }

        $listingType = strtolower($validated['listingType'] ?? $validated['type'] ?? 'offer');
        $type = str_contains($listingType, 'request') ? 'request' : 'offer';

        $compensation = strtolower($validated['compensation_type'] ?? Resource::BARTER);
        if (! in_array($compensation, Resource::COMPENSATIONS, true)) {
            $compensation = Resource::BARTER;
        }

        // Compensation invariant: a PAID listing must carry a real price;
        // free/barter listings never carry one.
        if ($compensation === Resource::PAID && empty($validated['price'])) {
            return response()->json(['message' => 'A price is required for a paid listing.', 'errors' => ['price' => ['A price is required for a paid listing.']]], 422);
        }

        $gallery = $this->storeGalleryImages($request);

        $resource = Resource::create([
            'user_id' => $request->user()->id,
            'category_id' => Category::findOrCreateByName($validated['category'] ?? 'Tools')->id,
            'type' => $type,
            'compensation_type' => $compensation,
            // Price is stored only for a paid sale; free/barter keep it null so
            // a stale figure can never surface on a gift or trade.
            'price' => $compensation === Resource::PAID ? ($validated['price'] ?? null) : null,
            // Whether the seller welcomes a counter-offer. Only a paid listing
            // can say yes; a gift or a trade has no price to negotiate.
            'price_negotiable' => $compensation === Resource::PAID
                ? (bool) ($validated['price_negotiable'] ?? false)
                : false,
            // The return side of a barter. Advisory only — the owner still
            // accepts or rejects each proposal — so free/paid never retain it.
            'wanted_item' => $compensation === Resource::BARTER
                ? ($validated['wanted_item'] ?? null)
                : null,
            'condition' => $validated['condition'] ?? 'Good',
            'title' => $validated['title'],
            'description' => $validated['description'] ?? '',
            'location' => $validated['location'] ?? trim($validated['barangay'].', '.(\App\Support\Puroks::canonicalize($validated['purok_sitio']) ?? '')),
            'barangay' => $validated['barangay'],
            'purok_sitio' => $validated['purok_sitio'],
            'latitude' => $validated['latitude'] ?? null,
            'longitude' => $validated['longitude'] ?? null,
            'is_active' => true,
            'status' => Resource::ACTIVE,
            // Cover (first) image plus the ordered gallery. image_path is kept
            // in step so existing consumers (exchanges, admin, feed thumbnail)
            // need no change.
            'image_path' => $gallery[0] ?? null,
            'image_paths' => $gallery === [] ? null : $gallery,
        ]);

        $resource->load(['user', 'category']);

        return response()->json([
            'message' => 'Resource posted successfully!',
            'data' => $resource->toFrontendListing(),
        ], 201);
    }

    public function update(Request $request, $id)
    {
        $resource = Resource::where('user_id', $request->user()->id)->findOrFail($id);
        $validated = $request->validate([
            'title' => 'sometimes|required|string|max:255',
            'description' => 'nullable|string',
            'category' => 'nullable|string|max:255',
            'compensation_type' => 'nullable|in:free,barter,paid',
            'price' => 'nullable|numeric|min:0|max:9999999',
            // Whether a paid seller welcomes a counter-offer (ignored for
            // free/barter). See the normalisation below.
            'price_negotiable' => 'nullable|boolean',
            'location' => 'nullable|string|max:255',
            'barangay' => ['sometimes', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['sometimes', 'nullable', 'string', 'max:60', \App\Support\Puroks::rule()],
            // Exact pin, editable alongside the rest of the location.
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            // Owner lifecycle transitions. `closed` is accepted as a legacy
            // alias for `archived` so older builds keep working. Note that the
            // moderation states (flagged/hidden/removed) are deliberately NOT
            // in this list: whether the owner is even allowed to move the
            // listing at all is decided below against its CURRENT status, so a
            // member can never pull their listing out of a moderator's hold.
            'status' => 'sometimes|in:active,paused,traded,archived,closed',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
            'images' => 'nullable|array|max:6',
            'images.*' => 'image|mimes:jpg,jpeg,png|max:5120',
            'wanted_item' => 'nullable|string|max:160',
        ]);
        // A replace-the-gallery request wipes the old files and stores the new
        // set; an absent gallery (neither `images` nor `image`) leaves the
        // photos untouched. image_path tracks the new cover.
        if ($request->hasFile('images') || $request->hasFile('image')) {
            $this->deleteGalleryFiles($resource);
            $gallery = $this->storeGalleryImages($request);
            $resource->image_path = $gallery[0] ?? null;
            $resource->image_paths = $gallery === [] ? null : $gallery;
        }
        // `status` is excluded from mass-assignment for the same reason: it is
        // applied explicitly below under the closed-only rule above.
        $resource->fill(collect($validated)
            ->except(['category', 'image', 'images', 'compensation_type', 'price', 'price_negotiable', 'status'])
            ->all());
        if (array_key_exists('category', $validated)) {
            $resource->category_id = Category::findOrCreateByName($validated['category'] ?: 'Tools')->id;
        }
        if (array_key_exists('compensation_type', $validated)) {
            $resource->compensation_type = $validated['compensation_type'] ?: $resource->compensationType();
        }
        // The return side lives on barter listings only. Clearing it when the
        // compensation changes away from barter stops a stale "wanted" note
        // surfacing on what is now a gift or a sale — whether or not the
        // request carried an explicit wanted_item.
        if (array_key_exists('wanted_item', $validated) || array_key_exists('compensation_type', $validated)) {
            $resource->wanted_item = $resource->compensationType() === Resource::BARTER
                ? ($validated['wanted_item'] ?? $resource->wanted_item)
                : null;
        }
        // Keep price and mode consistent: a paid listing needs its figure,
        // anything else is stored as null.
        // A PAID listing must always end up with a price; free/barter never.
        $effectiveType = ($validated['compensation_type'] ?? null) ?: $resource->compensationType();
        if ($effectiveType === Resource::PAID) {
            $incomingPrice = array_key_exists('price', $validated) ? $validated['price'] : $resource->price;
            if (empty($incomingPrice) || (float) $incomingPrice <= 0) {
                return response()->json(['message' => 'A price is required for a paid listing.', 'errors' => ['price' => ['A price is required for a paid listing.']]], 422);
            }
        }

        if (array_key_exists('price', $validated)) {
            $resource->price = $resource->compensationType() === Resource::PAID
                ? $validated['price']
                : null;
        } elseif ($resource->compensationType() !== Resource::PAID) {
            $resource->price = null;
        }
        // "Price negotiable" is a paid-only attribute: keep it in step with the
        // compensation so a listing that becomes a gift/trade never keeps
        // offering a counter-offer it cannot honour.
        if ($resource->compensationType() !== Resource::PAID) {
            $resource->price_negotiable = false;
        } elseif (array_key_exists('price_negotiable', $validated)) {
            $resource->price_negotiable = (bool) $validated['price_negotiable'];
        }
        // A status change is an owner action, allowed only while the listing is
        // in an owner-controlled lifecycle state. Anything a moderator has
        // flagged/hidden/removed stays there — otherwise PATCH {status:"active"}
        // would silently undo a moderation decision.
        if (array_key_exists('status', $validated)) {
            if (! $resource->ownerControlsStatus()) {
                return response()->json([
                    'message' => 'This listing is under moderation review and cannot be changed here.',
                ], 403);
            }
            // Reactivating (Resume/Repost) is enough to bypass the unverified
            // posting cap if it were unchecked: a member could archive a
            // listing and restore it whenever they wanted a fourth slot. The
            // cap therefore applies to any move that makes a hidden listing
            // live again — but not to an edit of one that is already live.
            $target = $validated['status'] === 'closed' ? Resource::ARCHIVED : $validated['status'];
            if ($target === Resource::ACTIVE && ! $resource->isPubliclyVisible()) {
                if ($rejection = $this->unverifiedCapRejection($request)) {
                    return $rejection;
                }
            }
            $resource->applyOwnerStatus($validated['status']);
        }
        $resource->save();
        return response()->json(['message' => 'Listing updated.', 'data' => $resource->fresh(['user', 'category'])->toFrontendListing()]);
    }

    /**
     * Archive rather than hard-delete.
     *
     * The row and its photo are kept so the owner can restore it, and so the
     * exchanges/conversations that reference the listing keep resolving. Only
     * an admin can truly remove a listing. `DELETE` is retained (instead of
     * just `PATCH {status:"archived"}`) so older app builds that still call it
     * keep working.
     */
    public function destroy(Request $request, $id)
    {
        $resource = Resource::where('user_id', $request->user()->id)->findOrFail($id);
        if (! $resource->ownerControlsStatus()) {
            return response()->json([
                'message' => 'This listing is under moderation review and cannot be changed here.',
            ], 403);
        }

        $resource->applyOwnerStatus(Resource::ARCHIVED);
        $resource->save();

        return response()->json(['message' => 'Listing archived.']);
    }

    /**
     * The member's own listings — INCLUDING the paused, traded and archived
     * rows the public feed never returns. This is what backs "My Listings" and
     * its tabs; previously a closed listing disappeared with no way back.
     */
    public function mine(Request $request)
    {
        $resources = Resource::with(['user', 'category'])
            ->where('user_id', $request->user()->id)
            ->latest()
            ->get();

        $listings = $resources
            ->map(fn (Resource $resource) => $resource->toFrontendListing())
            ->values();

        $counts = ['all' => $resources->count()];
        foreach (Resource::LIFECYCLE_STATUSES as $status) {
            $counts[$status] = $resources
                ->filter(fn (Resource $r) => $r->statusKey() === $status)
                ->count();
        }
        // Listings a moderator has flagged/hidden/removed: shown, but read-only.
        $counts['held'] = $resources
            ->filter(fn (Resource $r) => $r->isModerationStatus())
            ->count();

        return response()->json([
            'listings' => $listings,
            // Legacy alias, mirroring the public feed's `data` key.
            'data' => $listings,
            'counts' => $counts,
            // Progressive-trust envelope so the client can show "2 of 3 active
            // listings" and point unverified members at verification. `max` is
            // null for a verified resident, who posts without limit.
            'limits' => [
                'verified' => (bool) $request->user()->is_verified,
                'active_used' => $counts[Resource::ACTIVE] ?? 0,
                'active_max' => $request->user()->is_verified
                    ? null
                    : Resource::UNVERIFIED_ACTIVE_LIMIT,
            ],
        ]);
    }

    /**
     * The 403 to return when an unverified member already holds the maximum
     * number of live listings — or null when one more may go live.
     *
     * Verified residents never hit the cap. Shared by store() (a new listing)
     * and update() (reactivating an archived/paused one) so the two paths
     * cannot drift apart into a way around the limit.
     */
    private function unverifiedCapRejection(Request $request)
    {
        $user = $request->user();
        if ($user->is_verified) {
            return null;
        }

        $live = Resource::where('user_id', $user->id)->publiclyVisible()->count();
        if ($live < Resource::UNVERIFIED_ACTIVE_LIMIT) {
            return null;
        }

        return response()->json([
            'message' => 'Unverified members can have up to '
                .Resource::UNVERIFIED_ACTIVE_LIMIT.' active listings. '
                .'Verify your residency to post more.',
            'verification_required' => true,
            'active_listings' => $live,
            'active_listings_limit' => Resource::UNVERIFIED_ACTIVE_LIMIT,
        ], 403);
    }

    /**
     * Store an uploaded photo gallery to the public disk.
     *
     * Reads the multi-photo `images[]` array, falling back to the legacy single
     * `image` field that older app builds still send, and returns the ordered
     * list of stored relative paths. Files are stored in the same
     * `listing-images` folder the single-image path always used.
     *
     * @return array<int, string>
     */
    private function storeGalleryImages(Request $request): array
    {
        $files = $request->file('images');
        if ($files === null) {
            $single = $request->file('image');
            $files = $single ? [$single] : [];
        } elseif (! is_array($files)) {
            $files = [$files];
        }

        $paths = [];
        foreach ($files as $file) {
            if (! $file) {
                continue;
            }
            $stored = $file->store('listing-images', 'public');
            if ($stored) {
                $paths[] = $stored;
            }
        }

        return $paths;
    }

    /** Delete every stored photo for a listing (cover + gallery). */
    private function deleteGalleryFiles(Resource $resource): void
    {
        foreach ($resource->imagePaths() as $path) {
            if ($path) {
                Storage::disk('public')->delete($path);
            }
        }
    }
}
