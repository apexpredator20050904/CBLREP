<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Exchange;
use App\Models\MemberNotification;
use App\Models\Resource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Member-facing barter API.
 *
 * The system is Direct Bartering only. A proposal is always two-way: the
 * member names the listing they want (`resource_id`) and what they put up in
 * return (`offered_resource_id` and/or `offered_item`). The validation below
 * makes the second half mandatory, so a one-sided gift cannot be created even
 * by a hand-crafted request — which is the property the panel defence rests on.
 *
 * Status authority is deliberately asymmetric:
 *
 *   owner of the requested listing → accept, reject, complete
 *   the proposer                  → cancel only
 *
 * If either side could accept, a proposer could agree to their own trade and
 * mark it settled without the owner ever seeing it.
 */
class ExchangeController extends Controller
{
    /**
     * Columns that belonged to the retired freecycling / lending features.
     *
     * Kept in one place so `store()` and `update()` cannot drift apart, and so
     * the message a stale client receives is the same on both endpoints.
     */
    private const RETIRED_FIELD_MESSAGES = [
        'return_date' => 'This field was removed with temporary lending — a barter has no return schedule.',
        'scheduled_return_date' => 'This field was removed with temporary lending — a barter has no return schedule.',
        'credits_exchanged' => 'This field was removed with time banking — a barter has no credit value.',
    ];

    // ------------------------------------------------------------------
    // GET /api/exchanges — the signed-in member's barter ledger
    // ------------------------------------------------------------------

    /**
     * Every proposal the member is party to, newest first, with both sides of
     * each trade and both users eager-loaded.
     *
     * The eager loads are what keep this off the N+1 path: a member typically
     * sees a screenful of rows, and without them each row would fire four
     * extra queries (requested listing, offered listing, owner, proposer).
     *
     * The `metrics` block replaces the old lending counters (items lent out,
     * cycles given) with barter figures, so nothing in the payload is left
     * describing a model the system no longer supports.
     */
    public function index(Request $request)
    {
        $userId = $request->user()->id;

        $exchanges = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
            ->where(fn ($query) => $query->where('receiver_id', $userId)
                ->orWhere('provider_id', $userId))
            ->latest()
            ->get();

        // A closure, not a chained where()->orWhere(), because the counts below
        // add further constraints. Chained, AND binds tighter than OR and the
        // count would silently over-count. Rebuilt per query because Eloquent
        // builders are stateful and the clones below would otherwise inherit
        // the previous call's constraints.
        $party = fn () => Exchange::query()
            ->where(fn ($query) => $query->where('receiver_id', $userId)
                ->orWhere('provider_id', $userId));

        $metrics = [
            'proposalsSent' => $party()->where('receiver_id', $userId)->count(),
            'proposalsReceived' => $party()->where('provider_id', $userId)->count(),
            'awaitingResponse' => $party()->where('status', Exchange::STATUS_PENDING)->count(),
            'tradesCompleted' => $party()->where('status', Exchange::STATUS_COMPLETED)->count(),
        ];

        // Shape once and reuse — `present()` walks four relations per row.
        $rows = $exchanges
            ->map(fn (Exchange $exchange) => $this->present($exchange, $userId))
            ->values();

        return response()->json([
            'status' => 'success',
            'metrics' => $metrics,
            'exchanges' => $rows,
            // The Flutter client reads `data`; keep both keys in step.
            'data' => $rows,
        ]);
    }

    // ------------------------------------------------------------------
    // POST /api/exchanges — propose a barter
    // ------------------------------------------------------------------

    public function store(Request $request)
    {
        $user = $request->user();

        $validated = $request->validate([
            'resource_id' => ['required', 'integer', 'exists:resources,id'],
            'offered_resource_id' => ['nullable', 'integer', 'exists:resources,id'],
            'offered_item' => ['nullable', 'string', 'max:160'],
            // Retired types are admitted here only so the check below can name
            // them. Anything outside barter + the retired list fails here.
            'exchange_type' => ['nullable', Rule::in([...Exchange::TYPES, ...Exchange::RETIRED_TYPES])],
            // Structured location: barangay must be one of the 20 official
            // Trinidad, Bohol barangays; a specific purok/sitio is mandatory.
            'barangay' => ['required', 'string', \App\Support\Barangays::rule()],
            'purok_sitio' => ['required', 'string', 'max:60', \App\Support\Puroks::rule()],
            // Retired columns are `prohibited`, not merely unvalidated: Laravel
            // would otherwise strip them silently and answer 201, leaving a
            // stale client believing it scheduled a loan or priced credits.
            'return_date' => ['prohibited'],
            'scheduled_return_date' => ['prohibited'],
            'credits_exchanged' => ['prohibited'],
            // 2nd argument is the custom *messages* map (3rd would be
            // attribute labels). Getting these two backwards makes Laravel
            // expand `:attribute` to the sentence itself, so the response
            // reads "The This field was removed… field is prohibited."
        ], self::RETIRED_FIELD_MESSAGES);

        if (in_array($validated['exchange_type'] ?? null, Exchange::RETIRED_TYPES, true)) {
            throw ValidationException::withMessages([
                'exchange_type' => 'This system supports direct bartering only. '
                    .'Freecycling and temporary lending were removed.',
            ]);
        }

        $wanted = Resource::where('is_active', true)->findOrFail($validated['resource_id']);
        abort_if($wanted->user_id === $user->id, 422, 'You cannot propose a trade for your own listing.');

        // The "in return" side is what separates a barter from a gift, so at
        // least one of the two forms must be present.
        if (empty($validated['offered_resource_id']) && blank($validated['offered_item'] ?? null)) {
            throw ValidationException::withMessages([
                'offered_item' => 'Name what you are offering in return — a direct barter requires both sides.',
            ]);
        }

        $exchange = DB::transaction(function () use ($validated, $wanted, $user) {
            $offered = null;

            // Guard the self-deal case that spans both sides of the trade.
            if (! empty($validated['offered_resource_id'])) {
                $offered = Resource::where('is_active', true)->find($validated['offered_resource_id']);

                abort_if(! $offered, 422, 'The listing you are offering is no longer available.');
                abort_if($offered->user_id !== $user->id, 422, 'You can only offer a listing that you own.');
                abort_if($offered->id === $wanted->id, 422, 'You cannot trade a listing for itself.');
            }

            $exchange = Exchange::create([
                'resource_id' => $wanted->id,
                'offered_resource_id' => $validated['offered_resource_id'] ?? null,
                'offered_item' => isset($validated['offered_item'])
                    ? trim($validated['offered_item'])
                    : null,
                'provider_id' => $wanted->user_id,
                'receiver_id' => $user->id,
                'exchange_type' => Exchange::TYPE_BARTER,
                'status' => Exchange::STATUS_PENDING,
                'barangay' => $validated['barangay'],
                'purok_sitio' => trim($validated['purok_sitio']),
            ]);

            $exchange->setRelation('resource', $wanted);
            $exchange->setRelation('offeredResource', $offered ?? null);

            MemberNotification::create([
                'user_id' => $wanted->user_id,
                'type' => 'exchange_request',
                'title' => 'New barter proposal',
                'body' => $user->name.' offered '.$exchange->offeredLabel().' in exchange for “'.$wanted->title.'”.',
                'data' => ['exchange_id' => $exchange->id, 'resource_id' => $wanted->id],
            ]);

            return $exchange;
        });

        return response()->json([
            'message' => 'Barter proposal sent.',
            'exchange' => $this->present($exchange, $user->id),
        ], 201);
    }

    // ------------------------------------------------------------------
    // PATCH /api/exchanges/{id} — member status action
    // ------------------------------------------------------------------

    /**
     * Accept, reject or cancel a proposal.
     *
     * Single-party completion is retired: `completed` is rejected here on
     * purpose and must flow through POST /exchanges/{id}/confirm-completion,
     * where BOTH parties confirm independently before the row is promoted.
     *
     * The legality of the remaining moves is decided by
     * `Exchange::canTransitionTo()`, the same adjacency list the admin
     * console uses — so a member and an admin cannot disagree about what the
     * workflow permits. Authority is checked per-target-status rather than
     * per-user because the two parties hold different powers over the
     * same row.
     */
    public function update(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', Rule::in([
                Exchange::STATUS_ACCEPTED,
                Exchange::STATUS_REJECTED,
                Exchange::STATUS_CANCELLED,
            ])],
        ]);

        $userId = $request->user()->id;
        $target = $validated['status'];

        $exchange = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
            ->where(fn ($q) => $q->where('provider_id', $userId)->orWhere('receiver_id', $userId))
            ->findOrFail($id);

        if (! $exchange->canTransitionTo($target)) {
            return response()->json([
                'message' => sprintf(
                    'A barter that is already %s cannot be marked "%s".',
                    strtolower($exchange->frontendStatus()),
                    $target,
                ),
            ], 422);
        }

        // Responding to a proposal (accept/reject) is the listing owner's call
        // only. Cancelling stays open to either side: anyone may walk away.
        //
        // The proposer is deliberately unable to accept, otherwise they could
        // agree to their own trade unilaterally.
        $ownerOnly = in_array($target, [
            Exchange::STATUS_ACCEPTED,
            Exchange::STATUS_REJECTED,
        ], true);

        abort_if(
            $ownerOnly && $exchange->provider_id !== $userId,
            403,
            'Only the owner of the listing can accept or decline this proposal.',
        );

        $exchange->update(['status' => $target]);
        $this->notifyOther($exchange, $userId, $target);

        return response()->json([
            'message' => 'Barter '.$target.'.',
            'exchange' => $this->present($exchange->fresh(), $userId),
        ]);
    }

    /**
     * PUT /api/exchanges/{id}/status — alias of update() kept for the older
     * Flutter client. Identical validation and authority rules, so the two
     * paths cannot drift. `completed` is NOT accepted here either — it must
     * go through confirmCompletion() below.
     */
    public function updateStatus(Request $request, $id)
    {
        return $this->update($request, $id);
    }

    // ------------------------------------------------------------------
    // POST /api/exchanges/{id}/confirm-completion — dual confirmation
    // ------------------------------------------------------------------

    /**
     * Record the caller's half of the dual confirmation.
     *
     * Rules:
     *   1. Only the proposer (receiver_id) or the owner (provider_id) may
     *      confirm — anyone else gets 403 (404 when the row is not theirs).
     *   2. Only an `accepted` barter can collect confirmations (422 otherwise).
     *   3. The caller's flag (proposer_confirmed / owner_confirmed) is set
     *      with its timestamp. Re-confirming is idempotent.
     *   4. When BOTH flags are true the exchange is promoted to `completed`
     *      and both listings are closed (is_active=false, status=traded).
     *   5. With only one flag set the row stays `accepted` (partially
     *      confirmed) so the app can show "Waiting for other party's
     *      confirmation".
     */
    public function confirmCompletion(Request $request, $id)
    {
        $userId = $request->user()->id;

        $exchange = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
            ->where(fn ($q) => $q->where('provider_id', $userId)->orWhere('receiver_id', $userId))
            ->findOrFail($id);

        abort_if(
            $exchange->receiver_id !== $userId && $exchange->provider_id !== $userId,
            403,
            'Only the proposer or the owner of this exchange can confirm completion.',
        );

        if ($exchange->status === Exchange::STATUS_COMPLETED) {
            return response()->json([
                'message' => 'Exchange already completed.',
                'exchange' => $this->present($exchange, $userId),
            ]);
        }

        abort_if(
            $exchange->status !== Exchange::STATUS_ACCEPTED,
            422,
            'Only an accepted barter can be confirmed as completed. The owner must accept it first.'
        );

        $isProposer = $exchange->receiver_id === $userId;

        $completed = DB::transaction(function () use ($exchange, $isProposer, $userId) {
            $now = now();

            // Lock the row so two simultaneous confirmations cannot both read
            // "one flag missing" and skip the promotion to completed.
            $locked = Exchange::whereKey($exchange->id)->lockForUpdate()->firstOrFail();

            if ($isProposer) {
                $locked->proposer_confirmed = true;
                $locked->proposer_confirmed_at ??= $now;
            } else {
                $locked->owner_confirmed = true;
                $locked->owner_confirmed_at ??= $now;
            }
            $locked->save();

            if ($locked->isDualConfirmed() && $locked->canTransitionTo(Exchange::STATUS_COMPLETED)) {
                $locked->status = Exchange::STATUS_COMPLETED;
                $locked->save();

                // Both listings changed hands — close them so they disappear
                // from the browse feed. Skill trades have no offered listing,
                // so that side is simply skipped.
                Resource::whereKey($locked->resource_id)
                    ->update(['is_active' => false, 'status' => 'traded']);
                if ($locked->offered_resource_id) {
                    Resource::whereKey($locked->offered_resource_id)
                        ->update(['is_active' => false, 'status' => 'traded']);
                }

                $this->notifyOther($locked, $userId, Exchange::STATUS_COMPLETED);
            }

            return $locked->fresh(['resource', 'offeredResource', 'receiver', 'provider']);
        });

        $bothConfirmed = $completed->isDualConfirmed();

        return response()->json([
            'message' => $bothConfirmed
                ? 'Both parties confirmed — exchange completed.'
                : "Your confirmation was recorded. Waiting for other party's confirmation.",
            'exchange' => $this->present($completed, $userId),
        ]);
    }

    // ------------------------------------------------------------------
    // Legacy barter-proposal aliases
    // ------------------------------------------------------------------

    /**
     * GET /api/barter-proposals — incoming + outgoing for the caller.
     *
     * Reads the exchange table. This route existed before the collapse and
     * both clients still call it, so it is kept as an alias over
     * [Exchange] rather than deleted — the response is the same shape
     * `BarterProposalController` produced, rebuilt from exchange relations.
     */
    public function barterProposals(Request $request)
    {
        $userId = $request->user()->id;

        // An exchange is "incoming" for the member who was asked to trade:
        // the provider (owner of the wanted listing). The proposer sees it as
        // "outgoing". Same partition the old barter_proposals endpoint used.
        $incoming = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
            ->where('provider_id', $userId)
            ->latest()
            ->get()
            ->map(fn (Exchange $e) => $this->present($e, $userId))
            ->values();

        $outgoing = Exchange::with(['resource', 'offeredResource', 'receiver', 'provider'])
            ->where('receiver_id', $userId)
            ->latest()
            ->get()
            ->map(fn (Exchange $e) => $this->present($e, $userId))
            ->values();

        return response()->json([
            'incoming' => $incoming,
            'outgoing' => $outgoing,
        ]);
    }

    /**
     * PATCH /api/barter-proposals/{id}/status — accept / reject / complete.
     *
     * Alias of [update()]. `completed` is accepted here too and routed to
     * [confirmCompletion()], because the exchange state machine only allows
     * single-party completion through the dual-confirmation path — the
     * weaker direct "mark completed" transition the old barter flow allowed
     * is gone with the table.
     */
    public function barterProposalStatus(Request $request, $id)
    {
        $validated = $request->validate([
            'status' => ['required', Rule::in([
                Exchange::STATUS_ACCEPTED,
                Exchange::STATUS_REJECTED,
                Exchange::STATUS_CANCELLED,
                Exchange::STATUS_COMPLETED,
            ])],
        ]);

        if ($validated['status'] === Exchange::STATUS_COMPLETED) {
            return $this->confirmCompletion($request, (int) $id);
        }

        return $this->update($request, $id);
    }

    /**
     * POST /api/barter-proposals — propose a trade.
     *
     * Alias of [store()]. Both sides of the trade are required, so the
     * collapse also removes the old path's ability to create a one-sided
     * "proposal" that was really a gift.
     */
    public function storeBarterProposal(Request $request)
    {
        return $this->store($request);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /**
     * Shape one barter for the mobile client.
     *
     * `role` tells the app which side of the trade the signed-in member is on,
     * so the UI can render "Accept / Decline" for the owner and "Cancel" for
     * the proposer without re-deriving it from ids.
     */
    private function present(Exchange $exchange, int $viewerId): array
    {
        $isProposer = $exchange->receiver_id === $viewerId;

        return [
            'id' => $exchange->id,
            'type' => $exchange->frontendType(),
            'status' => $exchange->frontendStatus(),
            'raw_status' => $exchange->status,
            'barangay' => $exchange->barangay,
            'purok_sitio' => $exchange->purok_sitio,

            // Item requested from the owner
            'item' => $exchange->requestedLabel(),

            // Item the proposer puts up in return
            'offered' => $exchange->offeredLabel(),

            'withUser' => ($isProposer ? $exchange->provider : $exchange->receiver)?->name ?? 'Community Member',
            'role' => $isProposer ? 'proposer' : 'owner',
            'can_respond' => ! $isProposer && $exchange->status === Exchange::STATUS_PENDING,
            'can_cancel' => in_array($exchange->status, [
                Exchange::STATUS_PENDING,
                Exchange::STATUS_ACCEPTED,
            ], true),

            // ── Dual-confirmation progress ────────────────────────────
            // `i_confirmed` drives the button state (confirmed → disabled
            // check); the two flags + label drive the status indicator.
            'proposer_confirmed' => (bool) $exchange->proposer_confirmed,
            'owner_confirmed' => (bool) $exchange->owner_confirmed,
            'proposer_confirmed_at' => $exchange->proposer_confirmed_at?->toISOString(),
            'owner_confirmed_at' => $exchange->owner_confirmed_at?->toISOString(),
            'i_confirmed' => $exchange->hasConfirmed($viewerId),
            'can_confirm_completion' => $exchange->status === Exchange::STATUS_ACCEPTED
                && ! $exchange->hasConfirmed($viewerId),
            'confirmation_label' => $exchange->confirmationLabel(),

            'initiated' => $exchange->created_at?->format('M j, Y') ?? 'Today',
            'dueCompleted' => $exchange->status === Exchange::STATUS_COMPLETED
                ? $exchange->updated_at?->format('M j, Y')
                : '—',

            // ── Legacy barter-proposal keys ───────────────────────────
            // `GET /api/barter-proposals` now reads the exchange table, and
            // both clients (Flutter inbox, admin Barter Requests page) still
            // read these field names. They are aliases of the values above,
            // computed from the same relations — one model, one shape.
            'direction' => $isProposer ? 'outgoing' : 'incoming',
            'counterparty' => ($isProposer ? $exchange->provider : $exchange->receiver)?->name ?? 'Member',
            'created_at' => $exchange->created_at?->format('M j, Y') ?? 'Today',
            'offered_item' => $this->itemPayload($exchange->offeredResource),
            'requested_item' => $this->itemPayload($exchange->resource),
        ];
    }

    /** Title + photo + location for one side of a trade. */
    private function itemPayload(?Resource $resource): ?array
    {
        if (! $resource) {
            return null;
        }

        return [
            'id' => $resource->id,
            'title' => $resource->title,
            'image_url' => $resource->image_path ? asset('storage/'.$resource->image_path) : null,
            'location' => $resource->location,
        ];
    }

    /** Tell the counterparty their proposal moved. */
    private function notifyOther(Exchange $exchange, int $actorId, string $status): void
    {
        $recipientId = $exchange->provider_id === $actorId
            ? $exchange->receiver_id
            : $exchange->provider_id;

        try {
            MemberNotification::create([
                'user_id' => $recipientId,
                'type' => 'exchange_update',
                'title' => 'Barter '.strtolower($exchange->frontendStatus()),
                'body' => $exchange->requestedLabel().' ↔ '.$exchange->offeredLabel()
                    .' is now '.$exchange->frontendStatus().'.',
                'data' => ['exchange_id' => $exchange->id, 'status' => $status],
            ]);
        } catch (\Throwable $e) {
            // A notification failure must not roll back the status change.
            report($e);
        }
    }
}
