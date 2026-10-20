<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'app' => 'CBLREP — Community-Based Learning & Resource Exchange Portal',
        'status' => 'ok',
        'database' => config('database.connections.mysql.database'),
        'pages' => '/api/pages',
    ]);
});

// ── Public content pages (anonymous) ───────────────────────────────────────
// Published municipal pages created from /admin/content. Lives here (web.php)
// rather than behind the auth:admin group in api.php so any visitor — or the
// Flutter app — can read them without signing in.
Route::get('/api/pages', [\App\Http\Controllers\Api\ContentPageController::class, 'index']);
Route::get('/api/page/{slug}', [\App\Http\Controllers\Api\ContentPageController::class, 'show']);
