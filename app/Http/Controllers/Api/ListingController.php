<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Resource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class ListingController extends Controller
{
    public function index()
    {
        $listings = Resource::with(['user', 'category'])
            ->where('is_active', true)
            ->latest()
            ->get()
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
            'exchangeType' => 'nullable|string|max:255',
            'exchange_type' => 'nullable|string|max:255',
            'condition' => 'nullable|string|max:255',
            'location' => 'nullable|string|max:255',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
        ]);

        $listingType = strtolower($validated['listingType'] ?? $validated['type'] ?? 'offer');
        $type = str_contains($listingType, 'request') ? 'request' : 'offer';

        $resource = Resource::create([
            'user_id' => $request->user()->id,
            'category_id' => Category::findOrCreateByName($validated['category'] ?? 'Tools')->id,
            'type' => $type,
            'exchange_type' => $validated['exchangeType'] ?? $validated['exchange_type'] ?? 'Lend',
            'condition' => $validated['condition'] ?? 'Good',
            'title' => $validated['title'],
            'description' => $validated['description'] ?? '',
            'location' => $validated['location'] ?? $request->user()->barangay_or_location ?? 'Barangay 14',
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
            'location' => 'nullable|string|max:255',
            'status' => 'sometimes|in:active,closed',
            'image' => 'nullable|image|mimes:jpg,jpeg,png|max:5120',
        ]);
        if ($request->hasFile('image')) {
            if ($resource->image_path) Storage::disk('public')->delete($resource->image_path);
            $resource->image_path = $request->file('image')->store('listing-images', 'public');
        }
        $resource->fill(collect($validated)->except(['category', 'image'])->all());
        if (array_key_exists('category', $validated)) {
            $resource->category_id = Category::findOrCreateByName($validated['category'] ?: 'Tools')->id;
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
