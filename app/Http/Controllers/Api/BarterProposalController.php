<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BarterProposal;
use App\Models\MemberNotification;
use App\Models\Resource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Barter proposals: item-for-item trade negotiation between two members.
 *
 * Guards:
 *  - a user can never barter their own item (sender must own the offered
 *    item, and must NOT own the requested one);
 *  - trades only reference active listings — closed/traded rows 422.
 */
class BarterProposalController extends Controller
{
    /** GET /api/barter-proposals — incoming + outgoing for the caller. */
    public function index(Request $request)
    {
        $userId = $request->user()->id;

        $incoming = BarterProposal::with(['sender', 'offeredItem', 'requestedItem'])
            ->where('receiver_id', $userId)->latest()->get()
            ->map(fn (BarterProposal $p) => $this->present($p, 'incoming'));

        $outgoing = BarterProposal::with(['receiver', 'offeredItem', 'requestedItem'])
            ->where('sender_id', $userId)->latest()->get()
            ->map(fn (BarterProposal $p) => $this->present($p, 'outgoing'));

        return response()->json([
            'incoming' => $incoming,
            'outgoing' => $outgoing,
        ]);
    }

    /** POST /api/barter-proposals — propose a trade. */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'offered_item_id' => ['required', 'integer', 'exists:resources,id'],
            'requested_item_id' => ['required', 'integer', 'exists:resources,id', 'different:offered_item_id'],
        ]);

        $user = $request->user();

        $offered = Resource::where('is_active', true)->find($validated['offered_item_id']);
        abort_if(! $offered, 422, 'The listing you offer is no longer available.');
        abort_if($offered->user_id !== $user->id, 422, 'You can only offer your own listings.');

        $requested = Resource::where('is_active', true)->find($validated['requested_item_id']);
        abort_if(! $requested, 422, 'The requested listing is no longer available.');
        abort_if($requested->user_id === $user->id, 422, 'You cannot barter your own item.');

        $proposal = DB::transaction(function () use ($validated, $requested, $user) {
            $proposal = BarterProposal::create([
                'sender_id' => $user->id,
                'receiver_id' => $requested->user_id,
                'offered_item_id' => $validated['offered_item_id'],
                'requested_item_id' => $validated['requested_item_id'],
                'status' => BarterProposal::STATUS_PENDING,
            ]);

            MemberNotification::create([
                'user_id' => $requested->user_id,
                'type' => 'barter_proposal',
                'title' => 'New barter proposal',
                'body' => $user->name.' proposed a trade for “'.$requested->title.'”.',
                'data' => ['barter_proposal_id' => $proposal->id],
            ]);

            return $proposal;
        });

        $proposal->load(['sender', 'receiver', 'offeredItem', 'requestedItem']);

        return response()->json([
            'message' => 'Barter proposal sent.',
            'proposal' => $this->present($proposal, 'outgoing'),
        ], 201);
    }

    /** PATCH /api/barter-proposals/{id}/status — accept / reject / complete. */
    public function updateStatus(Request $request, int $id)
    {
        $validated = $request->validate([
            'status' => ['required', Rule::in([
                BarterProposal::STATUS_ACCEPTED,
                BarterProposal::STATUS_REJECTED,
                BarterProposal::STATUS_COMPLETED,
            ])],
        ]);

        $proposal = BarterProposal::with(['sender', 'receiver', 'offeredItem', 'requestedItem'])
            ->findOrFail($id);

        $userId = $request->user()->id;
        abort_if($userId !== $proposal->sender_id && $userId !== $proposal->receiver_id, 403);

        // Only the receiver decides on a pending offer; either party may
        // close the loop once it is accepted.
        $target = $validated['status'];
        if ($proposal->status === BarterProposal::STATUS_PENDING) {
            abort_if($target === BarterProposal::STATUS_COMPLETED, 422, 'Accept the trade before completing it.');
            abort_if($userId !== $proposal->receiver_id, 403, 'Only the recipient can accept or reject this offer.');
        } elseif ($proposal->status === BarterProposal::STATUS_ACCEPTED) {
            abort_if($target !== BarterProposal::STATUS_COMPLETED, 422, 'An accepted trade can only be completed.');
        } else {
            abort(422, 'This proposal is already '.$proposal->statusLabel().'.');
        }

        $proposal->update(['status' => $target]);

        // On completion, retire both listings from circulation.
        if ($target === BarterProposal::STATUS_COMPLETED) {
            Resource::whereIn('id', [$proposal->offered_item_id, $proposal->requested_item_id])
                ->update(['is_active' => false, 'status' => 'traded']);
        }

        $other = $userId === $proposal->sender_id ? $proposal->receiver_id : $proposal->sender_id;
        MemberNotification::create([
            'user_id' => $other,
            'type' => 'barter_proposal_update',
            'title' => 'Barter '.$proposal->statusLabel().'!',
            'body' => $request->user()->name.' marked the trade “'.$proposal->offeredItem?->title.'” ⇄ “'.$proposal->requestedItem?->title.'” as '.strtolower($proposal->statusLabel()).'.',
            'data' => ['barter_proposal_id' => $proposal->id],
        ]);

        return response()->json([
            'message' => 'Proposal marked '.$proposal->statusLabel().'.',
            'proposal' => $this->present($proposal->fresh(['sender', 'receiver', 'offeredItem', 'requestedItem']), $userId === $proposal->sender_id ? 'outgoing' : 'incoming'),
        ]);
    }

    private function present(BarterProposal $p, string $direction): array
    {
        return [
            'id' => $p->id,
            'direction' => $direction, // incoming | outgoing
            'status' => $p->statusLabel(),
            'raw_status' => $p->status,
            'offered_item' => $p->offeredItem ? [
                'id' => $p->offeredItem->id,
                'title' => $p->offeredItem->title,
                'image_url' => $p->offeredItem->image_path ? asset('storage/'.$p->offeredItem->image_path) : null,
                'location' => $p->offeredItem->location,
            ] : null,
            'requested_item' => $p->requestedItem ? [
                'id' => $p->requestedItem->id,
                'title' => $p->requestedItem->title,
                'image_url' => $p->requestedItem->image_path ? asset('storage/'.$p->requestedItem->image_path) : null,
                'location' => $p->requestedItem->location,
            ] : null,
            'counterparty' => $direction === 'incoming'
                ? ($p->sender?->name ?? 'Member')
                : ($p->receiver?->name ?? 'Member'),
            'created_at' => $p->created_at?->format('M j, Y') ?? 'Today',
        ];
    }
}
