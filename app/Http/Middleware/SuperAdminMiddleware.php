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

        // Single-account lockdown: only the designated Super Admin may proceed.
        if (! $user || $user->email !== AdminMiddleware::SUPER_ADMIN_EMAIL) {
            return response()->json([
                'message' => 'Unauthorized. Only the designated Super Administrator may perform this action.',
            ], 403);
        }

        return $next($request);
    }
}
