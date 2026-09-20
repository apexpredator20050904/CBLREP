<?php

use App\Http\Controllers\Api\AdminController;
use App\Http\Controllers\Api\AdminPortalController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ContentAdminController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\ExchangeController;
use App\Http\Controllers\Api\ListingController;
use App\Http\Controllers\Api\RealtimeController;
use App\Http\Controllers\Api\TimeBankController;
use App\Http\Controllers\Api\VerificationReportsController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public endpoints
|--------------------------------------------------------------------------
| Reachable without a token: auth entry points, read-only catalogues used
| by the mobile browse/map screens, and the realtime chat store.
*/

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);
Route::post('/admin-login', [AuthController::class, 'adminLogin']);
Route::get('/platform/status', [AdminPortalController::class, 'platformStatus']);

Route::get('/listings', [ListingController::class, 'index']);
Route::get('/timebank/services', [TimeBankController::class, 'services']);
Route::get('/timebank/service/{id}', [TimeBankController::class, 'show']);

Route::get('/messages', [RealtimeController::class, 'index']);
Route::post('/messages', [RealtimeController::class, 'store']);
Route::get('/stream', [RealtimeController::class, 'stream']);
Route::get('/presence', [RealtimeController::class, 'presenceIndex']);
Route::post('/presence', [RealtimeController::class, 'presenceStore']);

/*
|--------------------------------------------------------------------------
| Authenticated endpoints (Sanctum bearer token)
|--------------------------------------------------------------------------
*/

Route::middleware('auth:sanctum')->group(function () {
    // Session
    Route::get('/user', [AuthController::class, 'me']);
    Route::post('/logout', [AuthController::class, 'logout']);

    // Member dashboard
    Route::get('/dashboard/stats', [DashboardController::class, 'stats']);

    // Listings & exchanges
    Route::post('/listings', [ListingController::class, 'store']);
    Route::get('/exchanges', [ExchangeController::class, 'index']);
    Route::patch('/exchanges/{id}', [ExchangeController::class, 'update']);

    // Time Bank (contract documented in TimeBankController)
    Route::post('/timebank/services', [TimeBankController::class, 'storeService']);
    Route::get('/timebank/transactions', [TimeBankController::class, 'transactions']);
    Route::post('/timebank/transactions', [TimeBankController::class, 'requestService']);
    Route::get('/timebank/balance', [TimeBankController::class, 'balance']);
    Route::get('/timebank/stats', [TimeBankController::class, 'stats']);
    Route::patch('/timebank/transactions/{id}', [TimeBankController::class, 'updateTransaction']);

    /*
     * Admin portal — endpoints consumed by frontend/src/admin pages.
     * Every handler re-checks the admin role (AdminPortalController::guard).
     */
        Route::prefix('admin')->middleware('admin')->group(function () {
        Route::get('/dashboard', [AdminController::class, 'dashboard']);
        Route::get('/users', [AdminPortalController::class, 'users']);
        Route::post('/users/{id}/{action}', [AdminPortalController::class, 'userAction']);
        Route::get('/users/{id}/activity', [AdminPortalController::class, 'userActivity']);
        Route::get('/verification', [AdminPortalController::class, 'verification']);
        Route::get('/resources', [AdminPortalController::class, 'resources']);
        Route::post('/resources/{id}/moderate', [AdminPortalController::class, 'moderateResource']);
        Route::get('/exchanges', [AdminPortalController::class, 'exchanges']);
        Route::get('/reports', [VerificationReportsController::class, 'index']);
        Route::post('/reports/{id}/resolve', [VerificationReportsController::class, 'resolve']);
        Route::get('/map', [AdminPortalController::class, 'map']);
        Route::get('/analytics', [AdminPortalController::class, 'analytics']);
        Route::get('/analytics/export', [AdminPortalController::class, 'exportAnalytics']);
        Route::get('/timebank', [AdminPortalController::class, 'adminTimebank']);
        Route::get('/audit-logs', [AdminPortalController::class, 'auditLogs']);
        Route::get('/settings', [AdminPortalController::class, 'settings']);
        Route::post('/settings', [AdminPortalController::class, 'storeSettings']);
        Route::post('/settings/cache/clear', [AdminPortalController::class, 'clearCache']);
        Route::get('/settings/backup', [AdminPortalController::class, 'backup']);

        // ── Content management (/admin/content) ─────────────────────
        // Municipal pages with custom URL slugs (draft → published).
        Route::get('/content', [ContentAdminController::class, 'contentIndex']);
        Route::post('/content', [ContentAdminController::class, 'contentStore']);
        Route::patch('/content/{id}', [ContentAdminController::class, 'contentUpdate']);
        Route::delete('/content/{id}', [ContentAdminController::class, 'contentDestroy']);

        // ── Notifications & announcements (/admin/notifications) ────
        // Draft → scheduled/sent broadcasts targeted at member segments.
        Route::get('/notifications', [ContentAdminController::class, 'notifIndex']);
        Route::post('/notifications', [ContentAdminController::class, 'notifStore']);
        Route::post('/notifications/{id}/send', [ContentAdminController::class, 'notifSend']);
        Route::delete('/notifications/{id}', [ContentAdminController::class, 'notifDestroy']);
    });
});
