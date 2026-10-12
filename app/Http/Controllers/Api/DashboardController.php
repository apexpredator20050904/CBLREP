<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function stats(Request $request)
    {
        $user = $request->user();
        $barangay = $user->barangay_or_location;

        $recentListings = Resource::with(['user', 'category'])
            ->where('is_active', true)
            ->latest()
            ->take(4)
            ->get();

        $recentActivity = $recentListings->map(function (Resource $resource) {
            return [
                'icon' => '📦',
                'description' => ($resource->user?->name ?? 'A neighbor').' listed '.$resource->title,
                'time_ago' => $resource->created_at?->diffForHumans() ?? 'Just now',
            ];
        });

        // The `resources` mirror used to load EVERY active listing on each
        // call. The mobile LiveHubProvider polls this endpoint every 10
        // seconds, so that turned one background tick into a full-table read
        // and hydrate of every row. Capped to the same recent window the
        // summary cards already show; clients wanting the full feed should
        // call GET /listings, which is now paginated.
        $listings = Resource::with(['user', 'category'])
            ->where('is_active', true)
            ->latest()
            ->take(10)
            ->get()
            ->map(fn (Resource $resource) => $resource->toFrontendListing())
            ->values();

        return response()->json([
            'itemsAvailable' => Resource::where('is_active', true)->where('status', 'active')->count(),
            'activeExchanges' => Exchange::whereIn('status', ['pending', 'accepted'])->count(),
            'membersNearby' => $barangay
                ? User::where('barangay_or_location', $barangay)->count()
                : User::count(),
            'recentListings' => $recentListings->map(fn (Resource $resource) => $resource->toFrontendListing())->values(),
            'recentActivity' => $recentActivity->values(),
            'resources' => $listings,
        ]);
    }
}
