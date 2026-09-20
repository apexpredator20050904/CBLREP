<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\TimebankTransaction;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Live totals for the admin Overview page (OverviewPage.jsx).
 *
 * The remaining legacy admin handlers (users/listings/exchanges moderation)
 * were consolidated into AdminPortalController + VerificationReportsController,
 * which is what the admin portal actually consumes.
 */
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

        $recentActions = AuditLog::with('admin')->latest()->take(5)->get()->map(function (AuditLog $log) {
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
}
