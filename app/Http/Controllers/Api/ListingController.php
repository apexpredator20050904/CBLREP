<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Resource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ListingController extends Controller
{
    public function index(Request $request)
    {
        $query = Resource::with(['user', 'category'])
            ->where('is_active', true)
            ->latest();

        if ($barangay = trim((string) $request->query('barangay', ''))) {
            $query->where('barangay', $barangay);
        }
        if ($q = trim((string) $request->query('q', ''))) {
            $query->where(fn ($w) => $w
                ->where('title', 'like', "%{$q}%")
                ->orWhere('description', 'like', "%{$q}%")
                ->orWhere('location', 'like', "%{$q}%")
                ->orWhere('purok_sitio', 'like', "%{$q}%"));
        }

        $listings = $query->get()
            ->map(fn (Resource $resource) => $resource->toFrontendListing())
            ->values();

        return response()->json([
            'listings' => $listings,
            'data' => $listings,
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
            'status' => 'sometimes|in:active,closed',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
        ]);
        if ($request->hasFile('image')) {
            if ($resource->image_path) Storage::disk('public')->delete($resource->image_path);
            $resource->image_path = $request->file('image')->store('listing-images', 'public');
        }
        $resource->fill(collect($validated)->except(['category', 'image', 'compensation_type', 'price'])->all());
        if (array_key_exists('category', $validated)) {
            $resource->category_id = Category::findOrCreateByName($validated['category'] ?: 'Tools')->id;
        }
        if (array_key_exists('compensation_type', $validated)) {
            $resource->compensation_type = $validated['compensation_type'] ?: $resource->compensationType();
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
        $resource->is_active = ($validated['status'] ?? $resource->status) === 'active';
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
