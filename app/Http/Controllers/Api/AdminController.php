<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\SystemLog;
use App\Models\TimebankTransaction;
use App\Models\User;
use Illuminate\Http\Request;

class AdminController extends Controller
{
    public function dashboard(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $totalUsers = User::count();
        $verifiedUsersCount = User::where('is_verified', true)->count();
        $pendingVerificationCount = User::where('is_verified', false)->where('role', 'user')->count();
        $usersThisWeek = User::where('created_at', '>=', now()->startOfWeek())->count();

        $recentActions = SystemLog::with('admin')->latest()->take(5)->get()->map(function (SystemLog $log) {
            return [
                'title' => $log->action,
                'description' => ($log->admin?->name ?? 'Admin').' · '.($log->target_type ?? 'system'),
                'time' => $log->created_at?->diffForHumans() ?? now()->diffForHumans(),
                'type' => 'success',
            ];
        });

        if ($recentActions->isEmpty()) {
            $recentActions = collect([
                [
                    'title' => 'System connected',
                    'description' => 'Admin dashboard is reading live database totals',
                    'time' => now()->format('M j, Y H:i'),
                    'type' => 'success',
                ],
            ]);
        }

        return response()->json([
            'totalUsers' => $totalUsers,
            'usersDelta' => '+'.$usersThisWeek.' this week',
            'activeListings' => Resource::where('is_active', true)->where('status', 'active')->count(),
            'pendingReviewListings' => Resource::where('status', 'pending')->count(),
            'exchangesThisMonth' => Exchange::whereMonth('created_at', now()->month)
                ->whereYear('created_at', now()->year)
                ->count(),
            'totalExchanges' => Exchange::count(),
            'completedExchanges' => Exchange::where('status', 'completed')->count(),
            'totalTimeBankTransactions' => TimebankTransaction::count(),
            'pendingReports' => Resource::where('status', 'flagged')->count(),
            'openFlaggedContent' => Resource::where('status', 'flagged')->count(),
            'verifiedUsersCount' => $verifiedUsersCount,
            'verifiedUsersPercent' => $totalUsers > 0
                ? round(($verifiedUsersCount / $totalUsers) * 100).'%'
                : '0%',
            'pendingVerificationCount' => $pendingVerificationCount,
            'pendingVerificationPercent' => $totalUsers > 0
                ? round(($pendingVerificationCount / $totalUsers) * 100).'%'
                : '0%',
            'timeBankHoursTotal' => round((float) User::sum('time_bank_credits'), 1).' hrs',
            'recentActions' => $recentActions->values(),
        ]);
    }

    public function users(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $users = User::withCount('resources')
            ->latest()
            ->get()
            ->map(function (User $user) {
                return [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'role' => $user->role,
                    'is_verified' => (bool) $user->is_verified,
                    'time_bank_credits' => (float) $user->time_bank_credits,
                    'barangay_or_location' => $user->barangay_or_location,
                    'resources_count' => $user->resources_count,
                    'created_at' => $user->created_at?->format('M j, Y'),
                ];
            });

        return response()->json([
            'users' => $users,
            'total' => $users->count(),
        ]);
    }

    public function verifyUser(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $user = User::findOrFail($id);
        $user->update(['is_verified' => true]);

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Verified member '.$user->name,
            'target_type' => 'user',
            'target_id' => $user->id,
        ]);

        return response()->json([
            'message' => 'Member verified successfully.',
            'user' => $user->toFrontendArray(),
        ]);
    }

    public function updateUserRole(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $validated = $request->validate([
            'role' => 'required|in:user,admin',
        ]);

        $user = User::findOrFail($id);
        $user->update(['role' => $validated['role']]);

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Updated role for '.$user->name.' to '.$validated['role'],
            'target_type' => 'user',
            'target_id' => $user->id,
        ]);

        return response()->json([
            'message' => 'User role updated successfully.',
            'user' => $user->toFrontendArray(),
        ]);
    }

    public function deleteUser(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $user = User::findOrFail($id);
        if ($user->id === $request->user()->id) {
            return response()->json(['message' => 'You cannot delete your own account.'], 400);
        }

        $name = $user->name;
        $user->delete();

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Deleted member '.$name,
            'target_type' => 'user',
            'target_id' => $id,
        ]);

        return response()->json(['message' => 'Member deleted successfully.']);
    }

    public function listings(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $listings = Resource::with(['user', 'category'])
            ->latest()
            ->get()
            ->map(function (Resource $resource) {
                return [
                    'id' => $resource->id,
                    'title' => $resource->title,
                    'description' => $resource->description,
                    'category' => $resource->category?->name ?? 'Tools',
                    'type' => ucfirst($resource->type ?? 'offer'),
                    'exchange_type' => $resource->exchange_type ?? 'Lend',
                    'condition' => $resource->condition ?? 'Available',
                    'location' => $resource->location,
                    'status' => $resource->status ?? ($resource->is_active ? 'active' : 'closed'),
                    'is_active' => (bool) $resource->is_active,
                    'user' => [
                        'id' => $resource->user?->id,
                        'name' => $resource->user?->name ?? 'Member',
                    ],
                    'created_at' => $resource->created_at?->format('M j, Y'),
                ];
            });

        return response()->json([
            'listings' => $listings,
            'total' => $listings->count(),
        ]);
    }

    public function updateListingStatus(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $validated = $request->validate([
            'status' => 'required|in:active,pending,closed,flagged',
        ]);

        $resource = Resource::findOrFail($id);
        $resource->update([
            'status' => $validated['status'],
            'is_active' => $validated['status'] === 'active',
        ]);

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Updated listing "'.$resource->title.'" to '.$validated['status'],
            'target_type' => 'resource',
            'target_id' => $resource->id,
        ]);

        return response()->json([
            'message' => 'Listing status updated successfully.',
            'listing' => $resource->toFrontendListing(),
        ]);
    }

    public function deleteListing(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $resource = Resource::findOrFail($id);
        $title = $resource->title;
        $resource->delete();

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Deleted listing "'.$title.'"',
            'target_type' => 'resource',
            'target_id' => $id,
        ]);

        return response()->json(['message' => 'Listing deleted successfully.']);
    }

    public function exchanges(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $exchanges = Exchange::with(['resource', 'provider', 'receiver'])
            ->latest()
            ->get()
            ->map(function (Exchange $item) {
                return [
                    'id' => $item->id,
                    'type' => $item->frontendType(),
                    'item' => $item->resource?->title ?? 'Resource Exchange',
                    'provider' => $item->provider?->name ?? 'Member',
                    'receiver' => $item->receiver?->name ?? 'Member',
                    'status' => $item->frontendStatus(),
                    'raw_status' => $item->status,
                    'initiated' => $item->created_at?->format('M j, Y') ?? 'Today',
                    'dueCompleted' => $item->status === 'completed'
                        ? $item->updated_at?->format('M j, Y')
                        : ($item->scheduled_return_date?->format('M j, Y') ?? '—'),
                    'credits' => $item->credits_exchanged,
                ];
            });

        return response()->json([
            'exchanges' => $exchanges,
            'total' => $exchanges->count(),
        ]);
    }

    public function updateExchangeStatus(Request $request, $id)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $validated = $request->validate([
            'status' => 'required|in:pending,accepted,completed,cancelled',
        ]);

        $exchange = Exchange::findOrFail($id);
        $exchange->update(['status' => $validated['status']]);

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Updated exchange #'.$exchange->id.' to '.$validated['status'],
            'target_type' => 'exchange',
            'target_id' => $exchange->id,
        ]);

        return response()->json([
            'message' => 'Exchange status updated successfully.',
        ]);
    }

    public function logs(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $logs = SystemLog::with('admin')
            ->latest()
            ->take(50)
            ->get()
            ->map(function (SystemLog $log) {
                return [
                    'id' => $log->id,
                    'action' => $log->action,
                    'admin' => $log->admin?->name ?? 'System',
                    'target_type' => $log->target_type ?? 'system',
                    'target_id' => $log->target_id,
                    'time' => $log->created_at?->format('M j, Y H:i') ?? now()->format('M j, Y H:i'),
                ];
            });

        return response()->json([
            'logs' => $logs,
            'total' => $logs->count(),
        ]);
    }

    public function reports(Request $request)
    {
        if ($request->user()->role !== 'admin') {
            return response()->json(['message' => 'Unauthorized. Admin access required.'], 403);
        }

        $totalUsers = User::count();
        $totalListings = Resource::count();
        $totalExchanges = Exchange::count();
        $totalMessages = \App\Models\Message::count();

        $usersByBarangay = User::selectRaw('barangay_or_location, COUNT(*) as count')
            ->groupBy('barangay_or_location')
            ->get()
            ->map(fn ($row) => ['label' => $row->barangay_or_location ?? 'Unknown', 'count' => $row->count]);

        $listingsByCategory = Resource::with('category')
            ->get()
            ->groupBy(fn ($r) => $r->category?->name ?? 'Tools')
            ->map(fn ($group) => $group->count())
            ->map(fn ($count, $label) => ['label' => $label, 'count' => $count])
            ->values();

        $exchangesByType = Exchange::selectRaw('exchange_type, COUNT(*) as count')
            ->groupBy('exchange_type')
            ->get()
            ->map(fn ($row) => [
                'label' => ucfirst(str_replace('_', ' ', $row->exchange_type)),
                'count' => $row->count,
            ]);

        $exchangesByStatus = Exchange::selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->get()
            ->map(fn ($row) => [
                'label' => ucfirst($row->status),
                'count' => $row->count,
            ]);

        return response()->json([
            'totals' => [
                'users' => $totalUsers,
                'listings' => $totalListings,
                'exchanges' => $totalExchanges,
                'messages' => $totalMessages,
            ],
            'usersByBarangay' => $usersByBarangay,
            'listingsByCategory' => $listingsByCategory,
            'exchangesByType' => $exchangesByType,
            'exchangesByStatus' => $exchangesByStatus,
        ]);
    }
}