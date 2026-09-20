<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * RBAC middleware — ensures only authenticated users whose role
 * is exactly "admin" can access routes inside the /api/admin/* group.
 *
 * Used as:  Route::middleware(['auth:sanctum', 'admin'])->group(...)
 * or applied at the group level via bootstrap/app.php.
 *
 * Returns 403 with a JSON message for non-admins; the Sanctum guard
 * itself handles unauthenticated requests (401).
 */
class AdminMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user || $user->role !== 'admin') {
            return response()->json([
                'message' => 'Unauthorized. Admin access required.',
            ], 403);
        }

        return $next($request);
    }
}
