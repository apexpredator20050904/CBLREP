<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Resource;
use Illuminate\Http\Request;

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
        ]);

        $resource->load(['user', 'category']);

        return response()->json([
            'message' => 'Resource posted successfully!',
            'data' => $resource->toFrontendListing(),
        ], 201);
    }
}
