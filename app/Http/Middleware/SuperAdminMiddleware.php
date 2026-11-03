<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Elevated RBAC middleware — Super Admin only.
 *
 * Applied on top of the `admin` alias for the operations that must never
 * be available to a regular administrator: creating/deleting accounts,
 * changing role assignments and other destructive actions.
 *
 * Used as:  Route::middleware(['admin', 'super.admin'])->group(...)
 */
class SuperAdminMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Role-based authorization: the super_admin tier only. A regular
        // admin is a legitimate console user but may not change roles or
        // delete accounts.
        if (! $user || ! $user->isSuperAdmin()) {
            return response()->json([
                'message' => 'Unauthorized. Super Administrator access is required for this action.',
            ], 403);
        }

        return $next($request);
    }
}
