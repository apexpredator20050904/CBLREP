<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Resource;
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
            ->where('is_active', true)
            ->latest();

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
            'condition' => 'nullable|string|max:255',
            'location' => 'nullable|string|max:255',
            'barangay' => ['required', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['required', 'string', 'max:60', \App\Support\Puroks::rule()],
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
        ]);

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

        $resource = Resource::create([
            'user_id' => $request->user()->id,
            'category_id' => Category::findOrCreateByName($validated['category'] ?? 'Tools')->id,
            'type' => $type,
            'compensation_type' => $compensation,
            // Price is stored only for a paid sale; free/barter keep it null so
            // a stale figure can never surface on a gift or trade.
            'price' => $compensation === Resource::PAID ? ($validated['price'] ?? null) : null,
            // The return side of a barter. Advisory only — the owner still
            // accepts or rejects each proposal — so free/paid never retain it.
            'wanted_item' => $compensation === Resource::BARTER
                ? ($validated['wanted_item'] ?? null)
                : null,
            'condition' => $validated['condition'] ?? 'Good',
            'title' => $validated['title'],
            'description' => $validated['description'] ?? '',
            'location' => $validated['location'] ?? trim($validated['barangay'].', '.$validated['purok_sitio']),
            'barangay' => $validated['barangay'],
            'purok_sitio' => $validated['purok_sitio'],
            'latitude' => $validated['latitude'] ?? null,
            'longitude' => $validated['longitude'] ?? null,
            'is_active' => true,
            'status' => 'active',
            'image_path' => $request->file('image')?->store('listing-images', 'public'),
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
            'location' => 'nullable|string|max:255',
            'barangay' => ['sometimes', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['sometimes', 'nullable', 'string', 'max:60', \App\Support\Puroks::rule()],
            // A member may only CLOSE their own listing. `active` is
            // deliberately rejected: re-opening is an admin decision
            // (AdminPortalController::moderateResource), otherwise an owner
            // could PATCH {status:"active"} and undo a flagged/removed
            // moderation action on their own listing.
            'status' => 'sometimes|in:closed',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
            'wanted_item' => 'nullable|string|max:160',
        ]);
        if ($request->hasFile('image')) {
            if ($resource->image_path) Storage::disk('public')->delete($resource->image_path);
            $resource->image_path = $request->file('image')->store('listing-images', 'public');
        }
        // `status` is excluded from mass-assignment for the same reason: it is
        // applied explicitly below under the closed-only rule above.
        $resource->fill(collect($validated)
            ->except(['category', 'image', 'compensation_type', 'price', 'status'])
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
        // Only an explicit {status:"closed"} deactivates a listing. Absent
        // that, the current visibility is preserved — so editing the title of
        // a flagged listing does not silently re-activate or close it.
        if (array_key_exists('status', $validated)) {
            $resource->status = 'closed';
            $resource->is_active = false;
        }
        $resource->save();
        return response()->json(['message' => 'Listing updated.', 'data' => $resource->fresh(['user', 'category'])->toFrontendListing()]);
    }

    public function destroy(Request $request, $id)
    {
        $resource = Resource::where('user_id', $request->user()->id)->findOrFail($id);
        if ($resource->image_path) Storage::disk('public')->delete($resource->image_path);
        $resource->update(['is_active' => false, 'status' => 'closed']);
        return response()->json(['message' => 'Listing closed.']);
    }
}
