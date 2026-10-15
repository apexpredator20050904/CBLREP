<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Exchange;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Secure approval workflows — backs the frontend approval action buttons
 * on the ExchangesPage (/admin/exchanges).
 *
 * Dual-confirmation rule: completion is member-driven ONLY. Both parties
 * confirm via POST /api/exchanges/{id}/confirm-completion on the mobile app,
 * and the row promotes to `completed` once both flags are set. Admins can
 * approve / decline / cancel, but CANNOT mark a barter completed — that
 * status is rejected here on purpose.
 *
 * Every action:
 *   1. is reached only through auth:sanctum + admin middleware,
 *   2. re-checks the acting admin's role in code (defence in depth),
 *   3. validates the requested status transition against a whitelist,
 *   4. writes an audit_logs row (who, what, when, IP, user-agent),
 *   5. notifies the affected member where relevant.
 */
class AdminApprovalController extends Controller
{

    // ------------------------------------------------------------------
    // Exchange approval — POST /admin/exchanges/{id}/approve
    // ------------------------------------------------------------------

    /** Allowed exchange transitions (mirrors ExchangeController::updateStatus). */
    public function approveExchange(Request $request, $id)
    {
        $actor = $this->guard($request);

        $validated = $request->validate([
            'status' => ['required', Rule::in(['approved', 'rejected', 'cancelled'])],
            'reason' => ['nullable', 'string', 'max:1000'],
        ]);

        /** @var Exchange $exchange */
        $exchange = Exchange::with(['provider', 'receiver', 'resource', 'offeredResource'])
            ->findOrFail($id);

        $target = $validated['status'];

        // Normalise the console's vocabulary ("approved") onto the DB status
        // the mobile app reads ("accepted") before the legality check, so an
        // admin override is measured against the same rules a member faces.
        $dbStatus = $target === 'approved' ? Exchange::STATUS_ACCEPTED : $target;

        // Deliberately Exchange::canTransitionTo() and not a controller-local
        // map. An admin can act *on* a barter but cannot move it to a state a
        // member could not reach — otherwise the console would let someone mark
        // a trade settled before it was ever agreed, which is exactly the gap
        // the defence is about.
        if (! $exchange->canTransitionTo($dbStatus)) {
            return response()->json([
                'message' => sprintf(
                    'A %s barter cannot be marked "%s".',
                    $exchange->frontendStatus(),
                    $target,
                ),
                'allowed' => Exchange::TRANSITIONS[$exchange->status] ?? [],
            ], 422);
        }

        $exchange->status = $dbStatus;
        $exchange->save();

        $label = $exchange->requestedLabel().' ↔ '.$exchange->offeredLabel();

        AuditLog::record(
            $request,
            ucfirst($target).' exchange "'.$label.'" (EX-'.str_pad((string) $exchange->id, 5, '0', STR_PAD_LEFT).')',
            'exchange',
            $exchange->id,
            $validated['reason'] ?? null,
        );

        // Notify both parties.
        foreach (array_filter([$exchange->provider_id, $exchange->receiver_id]) as $userId) {
            try {
                app(NotificationService::class)->notify(
                    (int) $userId,
                    NotificationService::CATEGORY_EXCHANGES,
                    'exchange_update',
                    'Exchange '.ucfirst($target),
                    'Exchange "'.$label.'" was marked '.$target.' by an administrator'
                        .(($reason = trim((string) ($validated['reason'] ?? ''))) !== '' ? ': '.$reason : '.'),
                    ['exchange_id' => $exchange->id, 'status' => $dbStatus],
                );
            } catch (\Throwable $e) {
                report($e);
            }
        }

        return response()->json([
            'message' => 'Exchange '.$target.'.',
            'exchange_id' => $exchange->id,
            'status' => $target,
        ]);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private function guard(Request $request)
    {
        $user = $request->user();
        abort_unless($user && in_array($user->role, ['admin', 'super_admin'], true), 403, 'Unauthorized. Admin access required.');

        return $user;
    }

}
