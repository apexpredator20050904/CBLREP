<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Conversation;
use App\Models\Message;
use App\Models\Resource;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Direct inquiries — the Facebook-Marketplace-style chat behind every listing.
 *
 * A conversation can be plain member-to-member, or scoped to a listing
 * (listing_id + buyer_id + seller_id) so both parties always know which post a
 * thread is about. Free, barter and paid listings all use the same channel:
 * the community negotiates pickups, trades or payment informally here.
 */
class ConversationController extends Controller
{
    public function index(Request $request)
    {
        $userId = $request->user()->id;
        $conversations = Conversation::with([
            'participantOne:id,name,email',
            'participantTwo:id,name,email',
            'listing:id,title,compensation_type,price,image_path',
        ])
            ->where(fn ($q) => $q->where('participant_one_id', $userId)->orWhere('participant_two_id', $userId))
            ->withCount(['messages as unread_count' => fn ($q) => $q->whereNull('read_at')->where('sender_id', '!=', $userId)])
            ->orderByDesc('last_message_at')
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (Conversation $conversation) => $this->summary($conversation, $userId));

        return response()->json(['conversations' => $conversations->values()]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'user_id' => ['required', 'integer', 'exists:users,id'],
            // Optional: scope the inquiry to the listing it is about.
            'listing_id' => ['nullable', 'integer', 'exists:resources,id'],
        ]);
        abort_if((int) $validated['user_id'] === $request->user()->id, 422, 'You cannot start a conversation with yourself.');

        $me = $request->user()->id;

        // Listing-scoped inquiry: buyer = caller, seller = the other member.
        if (! empty($validated['listing_id'])) {
            $listing = Resource::findOrFail($validated['listing_id']);
            $sellerId = (int) $listing->user_id;
            abort_if($sellerId === $me, 422, 'You cannot inquire about your own listing.');
            abort_if($sellerId !== (int) $validated['user_id'], 422, 'The listing owner does not match the person you are messaging.');

            $conversation = Conversation::forListing(
                $listing->id,
                $me,
                $sellerId,
            );
        } else {
            $conversation = Conversation::between($me, (int) $validated['user_id']);
        }

        return response()->json([
            'conversation' => $this->summary($conversation, $me),
        ], 201);
    }

    public function messages(Request $request, int $id)
    {
        $conversation = $this->ownedConversation($request, $id);
        $conversation->messages()
            ->where('sender_id', '!=', $request->user()->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json([
            'conversation' => $this->summary($conversation, $request->user()->id),
            'messages' => $conversation->messages()->with('sender:id,name,email')->oldest()->get(),
        ]);
    }

    public function send(Request $request, int $id)
    {
        $conversation = $this->ownedConversation($request, $id);
        $validated = $request->validate(['body' => ['required', 'string', 'max:5000']]);

        $message = $conversation->messages()->create([
            'sender_id' => $request->user()->id,
            'body' => trim($validated['body']),
        ]);
        $conversation->update(['last_message_at' => now()]);

        $recipientId = $conversation->participant_one_id === $request->user()->id
            ? $conversation->participant_two_id
            : $conversation->participant_one_id;
        \App\Models\MemberNotification::create([
            'user_id' => $recipientId,
            'type' => 'message',
            'title' => 'New message from '.$request->user()->name,
            'body' => $message->body,
            'data' => [
                'conversation_id' => $conversation->id,
                'listing_id' => $conversation->listing_id,
            ],
        ]);

        return response()->json(['message' => $message->load('sender:id,name,email')], 201);
    }

    /**
     * Shape consumed by the mobile inbox and the admin Inquiries console.
     * Carries the listing's compensation badge so an inquiry can be read in
     * context ("PAID · ₱250") without a second request.
     */
    private function summary(Conversation $conversation, int $userId): array
    {
        $listing = $conversation->listing;

        return [
            'id' => $conversation->id,
            'member' => $conversation->otherParticipant($userId)?->only(['id', 'name', 'email']),
            'listing' => $listing ? [
                'id' => $listing->id,
                'title' => $listing->title,
                'compensation_type' => $listing->compensationType(),
                'compensation_label' => $listing->compensationLabel(),
                'price' => $listing->displayPrice(),
            ] : null,
            'last_message_at' => $conversation->last_message_at?->toISOString(),
            'unread_count' => (int) ($conversation->unread_count ?? 0),
        ];
    }

    private function ownedConversation(Request $request, int $id): Conversation
    {
        $userId = $request->user()->id;
        return Conversation::whereKey($id)
            ->where(fn ($q) => $q->where('participant_one_id', $userId)->orWhere('participant_two_id', $userId))
            ->firstOrFail();
    }
}
