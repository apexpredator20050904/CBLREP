<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Conversation;
use App\Models\MemberNotification;
use App\Models\Message;
use App\Models\Resource;
use App\Models\User;
use App\Services\NotificationService;
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
    /**
     * Attachment limits shared by both send endpoints (POST
     * /conversations/{id}/messages and POST /messages) so the two never drift.
     *
     * `max` is in kilobytes (Laravel's file-size unit): 51200 KB = 50 MB, sized
     * for short video clips. Allowed types are photos, documents and video.
     */
    private const ATTACHMENT_MAX_KB = 51200;

    private const ATTACHMENT_MIMES = 'jpg,jpeg,png,webp,pdf,doc,docx,txt,mp4,mov,m4v,webm,3gp';

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
            // Only a listing that is still publicly visible can be inquired
            // about. Without this check a member who knew the id could open a
            // thread about an ARCHIVED, TRADED or moderator-REMOVED listing
            // and the owner would still be notified about it — the barter
            // endpoint has always refused those, so the chat door was the way
            // around moderation.
            $listing = Resource::where('is_active', true)->find($validated['listing_id']);
            abort_if(! $listing, 404, 'That listing is no longer available.');
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
            // Soft-deleted rows are filtered by the Message global scope, so
            // a removed message disappears for both participants.
            'messages' => $conversation->messages()
                ->with('sender:id,name,email')
                ->oldest('id')
                ->get()
                ->map(fn (Message $message) => $message->toChatPayload())
                ->values(),
        ]);
    }

    public function send(Request $request, int $id)
    {
        $conversation = $this->ownedConversation($request, $id);
        $validated = $request->validate([
            'body' => ['nullable', 'string', 'max:5000'],
            // Messenger-style attachments: photos, documents + video clips.
            'file' => ['nullable', 'file', 'max:'.self::ATTACHMENT_MAX_KB, 'mimes:'.self::ATTACHMENT_MIMES],
        ]);

        $body = trim((string) ($validated['body'] ?? ''));
        $file = $request->file('file');

        if ($body === '' && ! $file) {
            return response()->json([
                'message' => 'A message needs text or an attachment.',
                'errors' => ['body' => ['A message needs text or an attachment.']],
            ], 422);
        }

        $attachment = $file ? $this->storeAttachment($file) : [];

        $message = $conversation->messages()->create([
            'sender_id' => $request->user()->id,
            'body' => $body,
            ...$attachment,
        ]);
        $conversation->update(['last_message_at' => now()]);

        $recipientId = $conversation->participant_one_id === $request->user()->id
            ? $conversation->participant_two_id
            : $conversation->participant_one_id;
        $this->notifyRecipient($conversation, $request->user(), $recipientId, $body, $attachment);

        return response()->json(['message' => $message->fresh('sender')->toChatPayload()], 201);
    }

    /**
     * Stores a chat attachment on the `public` disk under `chat_attachments/`
     * and returns the columns to persist on the message row.
     *
     * The type is resolved from the detected mime, falling back to the client
     * extension because a test/mock upload can arrive as octet-stream while
     * still carrying a .mp4 name.
     */
    private function storeAttachment(\Illuminate\Http\UploadedFile $file): array
    {
        $mime = (string) $file->getMimeType();
        $extension = strtolower((string) $file->getClientOriginalExtension());

        $isImage = str_starts_with($mime, 'image/')
            || in_array($extension, ['jpg', 'jpeg', 'png', 'webp'], true);

        $isVideo = ! $isImage && (
            str_starts_with($mime, 'video/')
            || in_array($extension, ['mp4', 'mov', 'm4v', 'webm', '3gp'], true)
        );

        $path = $file->store('chat_attachments', 'public');

        return [
            'file_path' => $path,
            'file_type' => $isImage ? 'image' : ($isVideo ? 'video' : 'document'),
            'file_name' => $file->getClientOriginalName(),
            'file_size' => $file->getSize(),
            'mime_type' => $mime ?: null,
        ];
    }

    /**
     * PUT /api/messages/{id} — edit a message you sent.
     *
     * Ownership is enforced twice over: the message must belong to a thread
     * the caller participates in (so a stranger gets 404, not 403, and cannot
     * probe for message ids), and it must have been sent by the caller.
     * `edited_at` is stamped so the recipient can see the text changed.
     */
    public function updateMessage(Request $request, int $messageId)
    {
        $message = $this->ownedMessage($request, $messageId);

        if ((int) $message->sender_id !== (int) $request->user()->id) {
            return response()->json(['message' => 'You can only edit messages you sent.'], 403);
        }

        // Text-only editing: attachments are immutable once sent, the caption
        // is what changes. Editing an attachment message with empty text keeps
        // the file row intact rather than orphaning it.
        $validated = $request->validate([
            'body' => ['required', 'string', 'max:5000'],
        ]);

        $body = trim($validated['body']);
        if ($body === '') {
            return response()->json([
                'message' => 'A message cannot be empty.',
                'errors' => ['body' => ['A message cannot be empty.']],
            ], 422);
        }

        $message->update([
            'body' => $body,
            'edited_at' => now(),
        ]);

        // Keep the recipient's inbox preview in step with the edited text.
        $conversation = $message->conversation;
        if ($conversation) {
            $recipientId = $conversation->participant_one_id === $request->user()->id
                ? $conversation->participant_two_id
                : $conversation->participant_one_id;
            \App\Models\MemberNotification::where('type', 'message')
                ->where('data->conversation_id', $conversation->id)
                ->latest('id')
                ->limit(1)
                ->update(['body' => $body]);
        }

        return response()->json(['message' => $message->fresh('sender')->toChatPayload()]);
    }

    /**
     * DELETE /api/messages/{id} — remove a message you sent.
     *
     * Soft delete: the row survives for the admin inquiry record, and the
     * Message model's global scope keeps it out of both participants' threads.
     */
    public function deleteMessage(Request $request, int $messageId)
    {
        $message = $this->ownedMessage($request, $messageId);

        if ((int) $message->sender_id !== (int) $request->user()->id) {
            return response()->json(['message' => 'You can only delete messages you sent.'], 403);
        }

        $conversation = $message->conversation;
        $message->delete();

        // Deleting the newest message must not leave the inbox preview
        // pointing at text that no longer exists.
        if ($conversation) {
            $replacement = $conversation->messages()
                ->withTrashed()
                ->latest('id')
                ->first();
            $conversation->update([
                'last_message_at' => $replacement?->created_at ?? $conversation->created_at,
            ]);
        }

        return response()->json(['deleted' => true, 'id' => $messageId]);
    }

    /**
     * POST /api/messages — direct send keyed on conversation_id.
     *
     * Supports multipart/form-data for Messenger-style attachments: text plus
     * an optional photo (jpg/png/webp), document (pdf/doc/docx/txt) or video
     * clip (mp4/mov/m4v/webm/3gp, up to 50 MB) stored under
     * storage/app/public/chat_attachments. Ownership is enforced through
     * the conversation lookup — non-participants get 404, never 403.
     */
    public function storeMessage(Request $request)
    {
        $validated = $request->validate([
            'conversation_id' => ['required', 'integer', 'exists:conversations,id'],
            'body' => ['nullable', 'string', 'max:5000'],
            'file' => ['nullable', 'file', 'max:'.self::ATTACHMENT_MAX_KB, 'mimes:'.self::ATTACHMENT_MIMES],
        ]);

        $conversation = $this->ownedConversation($request, (int) $validated['conversation_id']);

        $body = trim((string) ($validated['body'] ?? ''));
        $file = $request->file('file');

        if ($body === '' && ! $file) {
            return response()->json([
                'message' => 'A message needs text or an attachment.',
                'errors' => ['body' => ['A message needs text or an attachment.']],
            ], 422);
        }

        $attachment = $file ? $this->storeAttachment($file) : [];

        $message = $conversation->messages()->create([
            'sender_id' => $request->user()->id,
            'body' => $body,
            ...$attachment,
        ]);
        $conversation->update(['last_message_at' => now()]);

        $recipientId = $conversation->participant_one_id === $request->user()->id
            ? $conversation->participant_two_id
            : $conversation->participant_one_id;
        $this->notifyRecipient($conversation, $request->user(), $recipientId, $body, $attachment);

        return response()->json(['message' => $message->fresh('sender')->toChatPayload()], 201);
    }

    /**
     * Records the in-app notification for a new chat message and best-effort
     * pushes it to the recipient's devices.
     *
     * The `member_notifications` row is the source of truth (the mobile inbox
     * and the admin console read it); the FCM push is an enhancement that never
     * throws, so a push outage cannot break messaging.
     */
    private function notifyRecipient(
        Conversation $conversation,
        User $sender,
        int $recipientId,
        string $body,
        array $attachment,
    ): void {
        $preview = $body !== ''
            ? $body
            : ('Sent an attachment'.(isset($attachment['file_name']) ? ': '.$attachment['file_name'] : ''));
        $title = 'New message from '.$sender->name;

        app(NotificationService::class)->notify(
            $recipientId,
            NotificationService::CATEGORY_MESSAGES,
            'message',
            $title,
            $preview,
            [
                'conversation_id' => $conversation->id,
                'listing_id' => $conversation->listing_id,
            ],
        );
    }

    /**
     * Resolves a message the caller is a participant of.
     *
     * Scoping the lookup through the conversation (rather than fetching the
     * message directly) means a non-participant receives 404 — identical to a
     * message that does not exist, so ids cannot be probed.
     */
    private function ownedMessage(Request $request, int $messageId): Message
    {
        $userId = $request->user()->id;

        return Message::whereKey($messageId)
            ->whereHas('conversation', fn ($q) => $q
                ->where('participant_one_id', $userId)
                ->orWhere('participant_two_id', $userId))
            ->firstOrFail();
    }

    /**
     * Shape consumed by the mobile inbox and the admin Inquiries console.
     * Carries the listing's compensation badge so an inquiry can be read in
     * context ("PAID · ₱250") without a second request.
     */
    private function summary(Conversation $conversation, int $userId): array
    {
        $listing = $conversation->listing;
        $other = $conversation->otherParticipant($userId);

        return [
            'id' => $conversation->id,
            // Built explicitly rather than ->only([...]) so the avatarUrl()
            // accessor (not a column) is included for the inbox avatar.
            'member' => $other ? [
                'id' => $other->id,
                'name' => $other->name,
                'email' => $other->email,
                'avatar_url' => $other->avatarUrl(),
            ] : null,
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
