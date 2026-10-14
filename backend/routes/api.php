<?php

use App\Http\Controllers\Api\AdminApprovalController;
use App\Http\Controllers\Api\AdminController;
use App\Http\Controllers\Api\AdminPortalController;
use App\Http\Controllers\Api\AdminTwoFactorController;
use App\Http\Controllers\Api\AdminUserController;
use App\Http\Controllers\Api\AnalyticsController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ContentAdminController;
use App\Http\Controllers\Api\ConversationController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\DeviceTokenController;
use App\Http\Controllers\Api\ExchangeController;
use App\Http\Controllers\Api\ListingController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\VerificationReportsController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public endpoints
|--------------------------------------------------------------------------
| Reachable without a token: auth entry points, read-only catalogues used
| by the mobile browse/map screens.
*/

// Auth entry points. Each uses a named limiter from AppServiceProvider so
// credential stuffing, spam reset e-mails and code guessing stay expensive.
Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:auth-register');
Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:auth-login');
Route::post('/admin-login', [AuthController::class, 'adminLogin'])->middleware('throttle:auth-login');

/*
|--------------------------------------------------------------------------
| Admin two-factor authentication (stage 2)
|--------------------------------------------------------------------------
| Reached only after POST /admin-login has validated the primary credentials
| and issued a challenge. These sit OUTSIDE the auth:sanctum group on
| purpose — the administrator has no Sanctum token yet at this point; the
| challenge token in the body is what stands in for it.
|
| No `admin` middleware either: the role was already checked at stage 1, and
| `verify()` re-checks it before minting the token, so a demoted or
| suspended account still cannot get in.
|
| Throttles are tight because this is the only unauthenticated write path
| in the admin console, and its input space is 1,000,000 guesses.
*/
Route::prefix('admin/2fa')->middleware('throttle:admin-2fa')->group(function () {
    Route::post('/verify', [AdminTwoFactorController::class, 'verify']);

    // Login-time enrolment for an administrator with no authenticator yet.
    // Same public, enrol-token-gated model as /verify — the token can only
    // be obtained by passing the stage-1 password check. Failures answer
    // 422/429 rather than 401 so the shared axios interceptor never reads a
    // bad QR scan as a dead session.
    Route::post('/enrol/confirm', [AdminTwoFactorController::class, 'enrolConfirm']);
    Route::post('/enrol/skip', [AdminTwoFactorController::class, 'enrolSkip']);
});

/*
|--------------------------------------------------------------------------
| Admin 2FA enrolment and management
|--------------------------------------------------------------------------
| These require a live session, so they sit INSIDE the sanctum + admin group
| rather than with stage 2. An administrator who is already signed in is
| enrolling, disabling or rotating codes — not authenticating, so the
| password + live-code check lives inside the controller methods.
*/
Route::middleware(['auth:sanctum', 'admin'])->prefix('admin/2fa')->group(function () {
    Route::get('/status', [AdminTwoFactorController::class, 'status']);
    Route::post('/setup', [AdminTwoFactorController::class, 'setup'])->middleware('throttle:admin-2fa-setup');
    Route::post('/setup/confirm', [AdminTwoFactorController::class, 'confirm'])->middleware('throttle:admin-2fa-setup');
    Route::post('/disable', [AdminTwoFactorController::class, 'disable']);
    Route::post('/recovery-codes', [AdminTwoFactorController::class, 'regenerateRecoveryCodes']);
});
Route::post('/forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:password-email');
Route::post('/reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:password-reset');
Route::get('/platform/status', [AdminPortalController::class, 'platformStatus']);

// Public browse feed, used by the mobile home feed and the landing map.
// Throttled because it is unauthenticated and, before pagination was added,
// returned every active listing on each hit.
Route::get('/listings', [ListingController::class, 'index'])->middleware('throttle:public-read');

/*
|--------------------------------------------------------------------------
| Realtime presence
|--------------------------------------------------------------------------
| REMOVED. `/presence` was a JSON-file-backed presence/message store that no
| client called — Flutter and React both use the Sanctum conversation APIs
| instead. It accepted an unvalidated request body, had no throttle, and grew
| a single JSON file without bound. Routes and controller deleted together.
*/

/*
|--------------------------------------------------------------------------
| Authenticated endpoints (Sanctum bearer token)
|--------------------------------------------------------------------------
*/

Route::middleware('auth:sanctum')->group(function () {
    // Session
    Route::get('/user', [AuthController::class, 'me']);
    Route::patch('/user', [AuthController::class, 'updateProfile']);
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::post('/verification', [AuthController::class, 'submitVerification']);
    Route::get('/user/verification-status', [AuthController::class, 'verificationStatus']);

    // Member dashboard
    Route::get('/dashboard/stats', [DashboardController::class, 'stats']);

    // Listings & exchanges
    Route::post('/listings', [ListingController::class, 'store']);
    Route::patch('/listings/{id}', [ListingController::class, 'update']);
    Route::delete('/listings/{id}', [ListingController::class, 'destroy']);
    Route::get('/exchanges', [ExchangeController::class, 'index']);
    Route::post('/exchanges', [ExchangeController::class, 'store']);
    Route::patch('/exchanges/{id}', [ExchangeController::class, 'update']);
    Route::put('/exchanges/{id}/status', [ExchangeController::class, 'updateStatus']);
    // Dual-confirmation: both parties confirm the handover independently;
    // the exchange completes only when both flags are set.
    Route::post('/exchanges/{id}/confirm-completion', [ExchangeController::class, 'confirmCompletion']);

    // Barter proposals (item-for-item negotiation)
    // Barter proposals were collapsed into exchanges (migration
    // 2026_10_13_000001). These routes are kept as aliases over
    // ExchangeController so existing clients keep working unchanged — the
    // response is the same shape, rebuilt from exchange relations.
    Route::get('/barter-proposals', [ExchangeController::class, 'barterProposals']);
    Route::post('/barter-proposals', [ExchangeController::class, 'storeBarterProposal']);
    Route::patch('/barter-proposals/{id}/status', [ExchangeController::class, 'barterProposalStatus']);

    // Authenticated direct messaging.
    Route::get('/conversations', [ConversationController::class, 'index']);
    Route::post('/conversations', [ConversationController::class, 'store']);
    Route::get('/conversations/{id}/messages', [ConversationController::class, 'messages']);
    Route::post('/conversations/{id}/messages', [ConversationController::class, 'send']);

    // Per-message actions. Ownership is enforced in the controller: the
    // caller must be a participant of the thread AND the sender of that
    // message, so nobody can edit or remove somebody else's chat.
    // POST /messages accepts multipart/form-data (body + optional file) for
    // photo/document sharing into a conversation.
    Route::post('/messages', [ConversationController::class, 'storeMessage']);
    Route::put('/messages/{id}', [ConversationController::class, 'updateMessage']);
    Route::patch('/messages/{id}', [ConversationController::class, 'updateMessage']);
    Route::delete('/messages/{id}', [ConversationController::class, 'deleteMessage']);

    // Member announcements and action notifications.
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::put('/notifications/{id}/read', [NotificationController::class, 'read']);

    // FCM device tokens. The mobile app registers its token after sign-in and
    // removes it on sign-out so a signed-out device stops receiving pushes.
    Route::post('/device-tokens', [DeviceTokenController::class, 'store']);
    Route::delete('/device-tokens', [DeviceTokenController::class, 'destroy']);

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
        Route::get('/verification/{id}/document', [AdminPortalController::class, 'verificationDocument']);
        Route::get('/verification/{id}/history', [AdminPortalController::class, 'verificationHistory']);
        Route::get('/resources', [AdminPortalController::class, 'resources']);
        Route::post('/resources/{id}/moderate', [AdminPortalController::class, 'moderateResource']);

        // Direct inquiries on community listings (read + official reply).
        Route::get('/inquiries', [AdminPortalController::class, 'inquiries']);
        Route::get('/inquiries/{id}', [AdminPortalController::class, 'inquiryMessages']);
        Route::post('/inquiries/{id}/reply', [AdminPortalController::class, 'inquiryReply']);
        Route::get('/exchanges', [AdminPortalController::class, 'exchanges']);
        Route::get('/reports', [VerificationReportsController::class, 'index']);
        Route::post('/reports/{id}/resolve', [VerificationReportsController::class, 'resolve']);
        Route::get('/map', [AdminPortalController::class, 'map']);
        Route::get('/analytics', [AdminPortalController::class, 'analytics']);

        // ── Analytics exports (binary downloads) ────────────────────
        // Both accept an optional ?from=YYYY-MM-DD&to=YYYY-MM-DD window so an
        // export can be scoped to the date range selected on the Analytics
        // page. Throttled because each hit re-runs the aggregate queries and
        // renders a PDF.
        Route::get('/analytics/export/csv', [AnalyticsController::class, 'exportCsv'])
            ->middleware('throttle:admin-export');
        Route::get('/analytics/export/pdf', [AnalyticsController::class, 'exportPdf'])
            ->middleware('throttle:admin-export');

        Route::get('/audit-logs', [AdminPortalController::class, 'auditLogs']);
        Route::get('/settings', [AdminPortalController::class, 'settings']);
        Route::post('/settings', [AdminPortalController::class, 'storeSettings']);
        Route::post('/settings/cache/clear', [AdminPortalController::class, 'clearCache']);
        Route::get('/settings/backup', [AdminPortalController::class, 'backup']);

        // ── User & role management (/admin/accounts) ────────────────
        // Full CRUD for user/admin accounts. Reads + member-level edits
        // are available to any admin tier; role assignment, suspension of
        // admins and deletions are restricted to the super.admin tier.
        Route::get('/accounts', [AdminUserController::class, 'index']);
        Route::post('/accounts', [AdminUserController::class, 'store']);
        Route::patch('/accounts/{id}', [AdminUserController::class, 'update']);
        Route::middleware('super.admin')->group(function () {
            Route::patch('/accounts/{id}/role', [AdminUserController::class, 'updateRole']);
            Route::delete('/accounts/{id}', [AdminUserController::class, 'destroy']);
        });

        // ── Secure approval workflows ─────────────────────────────────
        // Exchange approve/complete/cancel with transition validation,
        // audit logging and member notifications. Listing moderation
        // (approve/flag/hide/remove/restore/edit) stays on
        // AdminPortalController::moderateResource (line above).
        Route::post('/exchanges/{id}/approve', [AdminApprovalController::class, 'approveExchange']);

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
