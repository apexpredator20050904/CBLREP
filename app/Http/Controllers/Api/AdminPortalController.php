<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdminSetting;
use App\Models\AuditLog;
use App\Models\Conversation;
use App\Models\Exchange;
use App\Models\Message;
use App\Models\Resource;
use App\Models\User;
use App\Models\VerificationHistory;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Admin portal endpoints backing src/admin/* pages.
 * Every handler enforces the admin role guard.
 */
class AdminPortalController extends Controller
{
    private function guard(Request $request): void
    {
        abort_unless($request->user()?->isAdmin(), 403, 'Unauthorized. Admin access required.');
    }

    /**
     * Centralised audit-log writer — delegates to AuditLog::record()
     * so every admin action is captured with IP + user-agent.
     */
    private function logAdminAction(Request $request, string $action, ?string $targetType = null, ?int $targetId = null, ?string $details = null): AuditLog
    {
        return AuditLog::record($request, $action, $targetType, $targetId, $details);
    }

    /** Public status consumed by the Flutter app before member actions. */
    public function platformStatus()
    {
        return response()->json([
            'maintenance' => AdminSetting::get('maintenanceMode', false),
            'message' => AdminSetting::value(
                'maintenanceMessage',
                'The Trinidad portal is undergoing scheduled municipal updates. Please check back soon.'
            ),
            'municipality' => 'Trinidad',
            'province' => 'Bohol',
        ]);
    }

    // ------------------------------------------------------------------
    // Users
    // ------------------------------------------------------------------

    public function users(Request $request)
    {
        $this->guard($request);

        $query = User::query()->withCount('resources')->latest();

        if ($q = trim((string) $request->query('q'))) {
            $query->where(function ($w) use ($q) {
                $w->where('name', 'like', "%{$q}%")
                    ->orWhere('email', 'like', "%{$q}%");
            });
        }

        // Frontend roles: member | community | admin  ->  DB roles: user | admin
        $roleMap = ['member' => 'user', 'community' => 'user', 'admin' => 'admin'];
        if ($role = $request->query('role')) {
            if ($mapped = $roleMap[$role] ?? null) {
                $query->where('role', $mapped);
            }
        }

        if ($request->query('status') === 'suspended') {
            $query->where('account_status', 'suspended');
        }

        // Barangay-level filter for the Trinidad community directory.
        if ($barangay = trim((string) $request->query('barangay'))) {
            $query->where('barangay_or_location', 'like', "%{$barangay}%");
        }

        $users = $query->get()->map(fn (User $u) => [
            'id' => $u->id,
            'name' => $u->name,
            'fullName' => $u->name,
            'avatar_url' => $u->avatarUrl(),
            'email' => $u->email,
            'role' => $u->isAdmin() ? 'System Administrator' : 'General Member',
            'raw_role' => $u->role,
            'verification_status' => $u->verificationStatusLabel(),
            'account_status' => $u->accountStatusLabel(),
            'is_verified' => (bool) $u->is_verified,
            'is_student' => (bool) $u->student_status,
            'student_school' => $u->student_school,
            'barangay_or_location' => $u->barangay_or_location,
            'resources_count' => $u->resources_count,
            'date_registered' => $u->created_at?->format('M j, Y'),
        ]);

        return response()->json(['users' => $users, 'total' => $users->count()]);
    }

    /**
     * One route serves verify / reject / request-info / suspend / reactivate.
     */
    public function userAction(Request $request, $id, $action)
    {
        $this->guard($request);

        $validated = $request->validate([
            'reason' => ['nullable', 'string', 'max:1000'],
        ]);
        $reason = trim((string) ($validated['reason'] ?? ''));

        /** @var User $user */
        $user = User::findOrFail($id);
        $logAction = null;

        switch ($action) {
            case 'verify':
                $user->forceFill(['is_verified' => true]);
                $user->verification_status = 'verified';
                // Approval note (optional) replaces any earlier rejection text.
                $user->verification_note = $reason !== '' ? $reason : null;
                // Allow the admin to capture student status during verification.
                if ($request->has('student_status') || $request->has('student_school')) {
                    $user->student_status = (bool) $request->input('student_status', $user->student_status ?? false);
                    $user->student_school = $request->input('student_school', $user->student_school);
                }
                $user->save();
                $logAction = 'Verified member '.$user->name;
                $details = $reason !== '' ? $reason : null;
                if ((bool) $user->student_status) {
                    $logAction = 'Verified student member '.$user->name
                        .' ('.($user->student_school ?? 'school not specified').')';
                }
                break;

            case 'reject':
                if ($reason === '') {
                    abort(422, 'A rejection reason is required.');
                }
                $user->verification_status = 'rejected';
                $user->verification_note = $reason;
                $user->save();
                $logAction = 'Rejected verification of '.$user->name;
                $details = $reason;
                break;

            case 'request-info':
                if ($reason === '') {
                    abort(422, 'Describe the information needed.');
                }
                $logAction = 'Verification info requested from '.$user->name;
                $details = $reason;
                break;

            case 'suspend':
                $user->account_status = 'suspended';
                if ($reason !== '') {
                    $user->admin_note = $reason;
                }
                $user->save();
                $logAction = 'Suspended member '.$user->name;
                $details = $reason !== '' ? $reason : null;
                break;

            case 'reactivate':
                $user->account_status = 'active';
                $user->save();
                $logAction = 'Reactivated member '.$user->name;
                $details = null;
                break;

            default:
                abort(422, 'Unsupported action.');
        }

        $this->logAdminAction($request, $logAction ?? ucfirst($action).' recorded for '.$user->name, 'user', $user->id, $details);
        VerificationHistory::create([
            'user_id' => $user->id,
            'admin_id' => $request->user()->id,
            'action' => $action,
            'status' => $user->verification_status,
            'note' => $details ?? $reason ?: null,
        ]);

        // Tell the member. Before this, a verification decision — the one
        // action a member is actively waiting on — produced no alert at all.
        $this->notifyMemberOfAction($user, $action, $reason);

        return response()->json([
            'message' => 'User '.$action.' successful.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    /**
     * Send the member an in-app alert (and push) for an account action.
     *
     * Unknown actions are silently skipped so this can never break the admin
     * request over a wording change.
     */
    private function notifyMemberOfAction(User $user, string $action, string $reason): void
    {
        [$title, $body, $type] = match ($action) {
            'verify' => [
                'You are now a verified member',
                'Your residency in Trinidad, Bohol has been verified. You can now post and trade with the community.'
                    .($reason !== '' ? ' Note: '.$reason : ''),
                'verification',
            ],
            'reject' => [
                'Verification not approved',
                $reason !== '' ? $reason : 'Your verification was not approved. You can re-submit with clearer details.',
                'verification',
            ],
            'request-info' => [
                'More information needed',
                $reason !== '' ? $reason : 'Please update your verification details so review can continue.',
                'verification',
            ],
            'suspend' => [
                'Your account was suspended',
                $reason !== '' ? $reason : 'Your account has been suspended by an administrator.',
                'account',
            ],
            'reactivate' => [
                'Your account was reactivated',
                'Your account is active again. Welcome back.',
                'account',
            ],
            default => [null, null, null],
        };

        if ($title === null) {
            return;
        }

        try {
            app(NotificationService::class)->notify(
                $user->id,
                NotificationService::CATEGORY_ACCOUNT,
                $type,
                $title,
                (string) $body,
                ['action' => $action],
            );
        } catch (\Throwable $e) {
            // An alert failure must never fail the admin action.
            report($e);
        }
    }

    public function verification(Request $request)
    {
        $this->guard($request);

        $query = User::where('is_verified', false)
            ->whereIn('verification_status', ['pending'])
            ->where('role', '!=', 'admin');

        // Barangay-level filter: restrict to a single Trinidad barangay.
        if ($barangay = trim((string) $request->query('barangay'))) {
            $query->where('barangay_or_location', 'like', "%{$barangay}%");
        }

        $pending = $query->latest()
            ->get()
            ->map(fn (User $u) => [
                'id' => $u->id,
                'fullName' => $u->name,
                'avatar_url' => $u->avatarUrl(),
                'email' => $u->email,
                'barangay' => $u->barangay_or_location,
                'is_student' => (bool) $u->student_status,
                'student_school' => $u->student_school,
                'role' => 'General Member',
                // The submitted proof of residency the reviewer must inspect.
                'document_type' => $u->verification_document_type,
                'has_document' => (bool) $u->verification_document_path,
                'submitted_at' => $u->verification_submitted_at?->toISOString(),
                'requested_at' => $u->verification_submitted_at?->diffForHumans()
                    ?? $u->created_at?->diffForHumans(),
            ])
            ->values();

        $decided = AuditLog::with('admin')
            ->where('target_type', 'user')
            ->where(function ($q) {
                $q->where('action', 'like', 'Verified%')
                    ->orWhere('action', 'like', 'Rejected%')
                    ->orWhere('action', 'like', 'Verification info requested%');
            })
            ->latest()
            ->take(25)
            ->get()
            ->map(fn (AuditLog $log) => [
                'id' => $log->id,
                'action' => $this->decisionLabel($log->action),
                'description' => $log->action,
                'date' => $log->created_at?->format('M j, Y'),
                'time' => $log->created_at?->format('H:i'),
            ]);

        $barangays = (clone $query)
            ->select('barangay_or_location')
            ->distinct()
            ->whereNotNull('barangay_or_location')
            ->pluck('barangay_or_location');

        return response()->json([
            'pending' => $pending,
            'decided' => $decided,
            'barangays' => $barangays,
        ]);
    }

    /**
     * GET /admin/verification/{id}/document — stream the member's submitted
     * proof of residency to an authenticated administrator. Proof documents
     * are sensitive (addresses / valid IDs), so they are never exposed on the
     * public disk; the admin token gates every read.
     */
    public function verificationDocument(Request $request, int $id)
    {
        $this->guard($request);

        /** @var User $user */
        $user = User::findOrFail($id);
        $path = (string) $user->verification_document_path;

        abort_if($path === '', 404, 'No verification document on file.');

        // Documents are written to the PRIVATE disk: proof of residency carries
        // an address / valid-ID image, so the file must never be reachable via
        // a guessed /storage/… URL. The admin token on this route is the gate.
        // Legacy rows written before the move still live on the public disk,
        // so fall back to it and in-flight submissions stay reviewable.
        foreach (['local', 'public'] as $disk) {
            if (Storage::disk($disk)->exists($path)) {
                return Storage::disk($disk)->response($path);
            }
        }

        abort(404, 'No verification document on file.');
    }

    public function verificationHistory(Request $request, int $id)
    {
        $this->guard($request);
        User::findOrFail($id);

        return response()->json([
            'history' => VerificationHistory::with('admin:id,name')
                ->where('user_id', $id)
                ->latest()
                ->get()
                ->map(fn (VerificationHistory $entry) => [
                    'id' => $entry->id,
                    'action' => $entry->action,
                    'status' => $entry->status,
                    'note' => $entry->note,
                    'admin' => $entry->admin?->name,
                    'created_at' => $entry->created_at?->toISOString(),
                ]),
        ]);
    }

    private function decisionLabel(string $action): string
    {
        return match (true) {
            str_starts_with($action, 'Verified') => 'Verified',
            str_starts_with($action, 'Rejected') => 'Rejected',
            str_starts_with($action, 'Verification info requested') => 'Info Requested',
            default => 'Decision',
        };
    }

    public function userActivity(Request $request, $id)
    {
        $this->guard($request);

        $user = User::findOrFail($id);
        $email = strtolower($user->email);

        return response()->json([
            'user' => [
                'id' => $user->id,
                'fullName' => $user->name,
                'email' => $user->email,
                'barangay' => $user->barangay_or_location,
                'is_student' => (bool) $user->student_status,
                'student_school' => $user->student_school,
                'role' => $user->isAdmin() ? 'System Administrator' : 'General Member',
            ],
            'listings' => Resource::where('user_id', $user->id)->latest()->take(20)
                ->get(['id', 'title', 'status', 'is_active'])->toArray(),
            // Report authorship is anonymous in this system by design.
            'reportsFiledBy' => [],
            'auditsMentioning' => AuditLog::where('target_type', 'user')
                ->where('target_id', $user->id)->latest()->take(10)
                ->get(['id', 'action'])
                ->map(fn (AuditLog $log) => [
                    'id' => $log->id,
                    'action' => $this->decisionLabel($log->action),
                    'description' => $log->action,
                ])->toArray(),
        ]);
    }

    // ------------------------------------------------------------------
    // Resources / moderation / map
    // ------------------------------------------------------------------

    private function adminStatusLabel(Resource $r): string
    {
        // Delegates to the model so the admin console and the app share one
        // label table (Active/Paused/Traded/Archived/Flagged/Hidden/Removed,
        // with legacy "closed" folded into Archived).
        return $r->statusLabel();
    }

    private function resourceRow(Resource $r): array
    {
        return [
            'id' => $r->id,
            'title' => $r->title,
            'name' => $r->title,               // AdminMapPage reads r.name
            'type' => ucfirst($r->type ?? 'offer'),
            'category' => $r->category?->name ?? 'Tools',
            'compensation_type' => $r->compensationType(),
            'compensation_label' => $r->compensationLabel(),
            'price' => $r->displayPrice(),
            'exchange_type' => $r->exchange_type ?? 'Lend',
            'owner' => $r->user?->name ?? 'Member',
            'user' => ['id' => $r->user?->id, 'name' => $r->user?->name ?? 'Member'],
            'status' => $r->statusKey(),
            'admin_status' => $this->adminStatusLabel($r),
            'location' => $r->location,
            'barangay' => $r->barangay,
            'purok_sitio' => $r->purok_sitio,
            'lat' => $r->latitude ?? \App\Support\BarangayLocations::for($r->location)[0],
            'lng' => $r->longitude ?? \App\Support\BarangayLocations::for($r->location)[1],
            'created_at' => $r->created_at?->format('M j, Y'),
            'image_url' => $r->image_path ? asset('storage/'.$r->image_path) : null,
        ];
    }

    public function resources(Request $request)
    {
        $this->guard($request);

        $kind = $request->query('kind', 'all');
        $query = Resource::with(['user', 'category'])->latest();

        $query->when($kind === 'offers', fn ($q) => $q->where('type', 'offer'))
            ->when($kind === 'needs', fn ($q) => $q->where('type', 'request'))
            ->when($kind === 'flagged', fn ($q) => $q->where('status', 'flagged'));

        $rows = $query->get()->map(fn (Resource $r) => $this->resourceRow($r))->values();

        return response()->json(['resources' => $rows, 'total' => $rows->count()]);
    }

        public function moderateResource(Request $request, $id)
    {
        $this->guard($request);

        $isEdit = $request->input('action') === 'edit';

        $validated = $request->validate([
            'action' => 'required|in:approve,flag,hide,remove,restore,edit',
            'reason' => 'nullable|string|max:1000',
            'title'        => $isEdit ? ['required', 'string', 'max:255'] : ['nullable'],
            'description'  => ['nullable', 'string'],
            'location'     => ['nullable', 'string', 'max:255'],
            'category_id'  => ['nullable', 'integer', 'exists:categories,id'],
        ]);

        $action = $validated['action'];
        $reason = trim((string) ($validated['reason'] ?? ''));

        $resource = Resource::findOrFail($id);

        // ---- Edit: update listing fields without changing status ----
        if ($action === 'edit') {
            $resource->update([
                'title'       => $validated['title'],
                'description' => $validated['description'] ?? $resource->description,
                'location'    => $validated['location'] ?? $resource->location,
                'category_id' => $validated['category_id'] ?? $resource->category_id,
            ]);

            $this->logAdminAction(
                $request,
                'Edited listing "'.$resource->title.'"',
                'resource',
                $resource->id,
                $reason !== '' ? $reason : null,
            );

            return response()->json([
                'message' => 'Listing "'.$resource->title.'" updated successfully.',
                'resource' => $this->resourceRow($resource),
            ]);
        }

        if (in_array($action, ['remove', 'hide'], true) && $reason === '') {
            return response()->json([
                'message' => 'A reason is required for moderation actions.',
            ], 422);
        }

        [$newStatus, $isActive] = match ($action) {
            'approve', 'restore' => ['active', true],
            'flag' => ['flagged', false],
            'hide' => ['hidden', false],
            'remove' => ['removed', false],
        };

        $resource->update(['status' => $newStatus, 'is_active' => $isActive]);

        $this->logAdminAction(
            $request,
            ucfirst($action).'d listing "'.$resource->title.'"'
                .($reason !== '' ? ' — '.$reason : ''),
            'resource',
            $resource->id,
        );

        // Tell the owner their listing moved. A member whose post was hidden or
        // removed previously had no way to know why it disappeared.
        $this->notifyOwnerOfModeration($resource, $action, $reason);

        return response()->json([
            'message' => 'Listing '.$action.'d successfully.',
            'resource' => $this->resourceRow($resource),
        ]);
    }

    /** Alert a listing's owner when a moderator acts on it. */
    private function notifyOwnerOfModeration(Resource $resource, string $action, string $reason): void
    {
        [$title, $body] = match ($action) {
            'flag' => [
                'Your listing was flagged',
                '"'.$resource->title.'" was flagged for review'
                    .($reason !== '' ? ': '.$reason : '.'),
            ],
            'hide' => [
                'Your listing was hidden',
                '"'.$resource->title.'" is hidden from the public feed'
                    .($reason !== '' ? ': '.$reason : '.'),
            ],
            'remove' => [
                'Your listing was removed',
                '"'.$resource->title.'" was removed'
                    .($reason !== '' ? ': '.$reason : '.'),
            ],
            'restore', 'approve' => [
                'Your listing is live again',
                '"'.$resource->title.'" is visible to the community again.',
            ],
            default => [null, null],
        };

        if ($title === null) {
            return;
        }

        try {
            app(NotificationService::class)->notify(
                $resource->user_id,
                NotificationService::CATEGORY_ACCOUNT,
                'listing',
                $title,
                (string) $body,
                ['resource_id' => $resource->id, 'status' => $resource->status],
            );
        } catch (\Throwable $e) {
            report($e);
        }
    }

    // ------------------------------------------------------------------
    // Direct inquiries (listing-scoped messaging oversight)
    // ------------------------------------------------------------------

    /** Shape a conversation for the admin Inquiries list. */
    private function inquiryRow(Conversation $c): array
    {
        $listing = $c->listing;
        $last = $c->messages->sortByDesc('id')->first();

        return [
            'id' => $c->id,
            'listing' => $listing ? [
                'id' => $listing->id,
                'title' => $listing->title,
                'compensation_type' => $listing->compensationType(),
                'compensation_label' => $listing->compensationLabel(),
                'price' => $listing->displayPrice(),
            ] : null,
            'buyer' => $c->buyer ? ['id' => $c->buyer->id, 'name' => $c->buyer->name] : null,
            'seller' => $c->seller ? ['id' => $c->seller->id, 'name' => $c->seller->name] : null,
            'message_count' => (int) ($c->message_count ?? $c->messages->count()),
            'last_message' => $last?->body,
            'last_message_at' => ($c->last_message_at ?? $last?->created_at)?->toISOString(),
            'updated_at' => $c->updated_at?->toISOString(),
        ];
    }

    /**
     * GET /admin/inquiries?q=&listing_id= — every direct inquiry on the
     * community's listings, scoped to the posts they belong to.
     */
    public function inquiries(Request $request)
    {
        $this->guard($request);

        $query = Conversation::with([
            'listing:id,title,compensation_type,price',
            'buyer:id,name',
            'seller:id,name',
            'messages' => fn ($q) => $q->latest()->limit(1),
        ])
            ->whereNotNull('listing_id')
            ->withCount('messages')
            ->orderByDesc('last_message_at')
            ->orderByDesc('updated_at');

        if ($listingId = $request->query('listing_id')) {
            $query->where('listing_id', (int) $listingId);
        }

        if ($q = trim((string) $request->query('q', ''))) {
            $query->where(function ($w) use ($q) {
                $w->whereHas('listing', fn ($l) => $l->where('title', 'like', "%{$q}%"))
                    ->orWhereHas('buyer', fn ($u) => $u->where('name', 'like', "%{$q}%"))
                    ->orWhereHas('seller', fn ($u) => $u->where('name', 'like', "%{$q}%"));
            });
        }

        $rows = $query->get()->map(fn (Conversation $c) => $this->inquiryRow($c))->values();

        return response()->json(['inquiries' => $rows, 'total' => $rows->count()]);
    }

    /**
     * GET /admin/inquiries/{id} — the full thread, marking the member side
     * read so the console can act as an answer desk.
     */
    public function inquiryMessages(Request $request, $id)
    {
        $this->guard($request);

        $conversation = Conversation::with([
            'listing:id,title,compensation_type,price,image_path',
            'buyer:id,name,email',
            'seller:id,name,email',
        ])->findOrFail($id);

        return response()->json([
            'inquiry' => $this->inquiryRow($conversation),
            'messages' => $conversation->messages()->with('sender:id,name,email')->oldest()->get(),
        ]);
    }

    /**
     * POST /admin/inquiries/{id}/reply — post an official reply into the
     * thread. Both members are notified so the answer reaches the negotiators.
     */
    public function inquiryReply(Request $request, $id)
    {
        $this->guard($request);

        $validated = $request->validate(['body' => ['required', 'string', 'max:5000']]);

        $conversation = Conversation::with(['listing:id,title'])->findOrFail($id);

        $message = $conversation->messages()->create([
            'sender_id' => $request->user()->id,
            'body' => trim($validated['body']),
        ]);
        $conversation->update(['last_message_at' => now()]);

        $listingTitle = $conversation->listing?->title;
        foreach ([$conversation->buyer_id, $conversation->seller_id] as $memberId) {
            if ($memberId) {
                app(NotificationService::class)->notify(
                    (int) $memberId,
                    NotificationService::CATEGORY_MESSAGES,
                    'message',
                    'CBLREP admin replied',
                    $listingTitle
                        ? "Regarding \"{$listingTitle}\": {$message->body}"
                        : $message->body,
                    ['conversation_id' => $conversation->id, 'listing_id' => $conversation->listing_id],
                );
            }
        }

        $this->logAdminAction(
            $request,
            'Replied to inquiry #'.$conversation->id.($listingTitle ? ' on "'.$listingTitle.'"' : ''),
            'conversation',
            $conversation->id,
        );

        return response()->json(['message' => $message->load('sender:id,name,email')], 201);
    }

    public function map(Request $request)
    {
        $this->guard($request);

        $filter = $request->query('filter', 'all');
        $query = Resource::with(['user', 'category'])->latest();

        $query->when($filter === 'offers', fn ($q) => $q->where('type', 'offer'))
            ->when($filter === 'needs', fn ($q) => $q->where('type', 'request'))
            ->when($filter === 'services', fn ($q) => $q->where('exchange_type', 'like', '%ime%'))
            ->when($filter === 'flagged', fn ($q) => $q->where('status', 'flagged'));

        $rows = $query->get()->map(fn (Resource $r) => $this->resourceRow($r))->values();

        return response()->json(['resources' => $rows, 'total' => $rows->count()]);
    }

    // ------------------------------------------------------------------
    // Exchanges (shape consumed by ExchangesPage)
    // ------------------------------------------------------------------

    public function exchanges(Request $request)
    {
        $this->guard($request);

        $statusFilter = $request->query('status', 'all');

        // The panel's status select -> DB statuses. `active` is the UI's word
        // for an agreed trade; `rejected` is listed separately from `cancelled`
        // so a decline can be told apart from a walk-away in the audit trail.
        $statusMap = [
            'pending' => 'pending',
            'active' => 'accepted',
            'completed' => 'completed',
            'rejected' => 'rejected',
            'cancel' => 'cancelled',
        ];

        // Both listings and both parties eager-loaded. Without this the table
        // fires six queries per row once the offered side is rendered.
        $query = Exchange::with([
            'resource', 'offeredResource', 'provider', 'receiver',
        ])->latest();

        if ($mappedStatus = $statusMap[$statusFilter] ?? null) {
            $query->where('status', $mappedStatus);
        }

        $rows = $query->get()->map(fn (Exchange $e) => [
            'id' => $e->id,
            'transaction_id' => 'EX-'.str_pad((string) $e->id, 5, '0', STR_PAD_LEFT),

            // Every row in this table is a direct barter, so the type column
            // is dropped rather than filtered — there is nothing to switch.
            'type' => $e->frontendType(),

            // Side A — the listing the owner is offering.
            'item_name' => $e->requestedLabel(),
            'resource' => $e->requestedLabel(),
            'resource_id' => $e->resource_id,

            // Side B — what the proposer puts up. Stated by listing id, by
            // free text, or both; `offeredLabel()` resolves all three.
            'offered_label' => $e->offeredLabel(),
            'offered_resource_id' => $e->offered_resource_id,
            'offered_item' => $e->offered_item,

            // Structured location of the trade (barangay + purok/sitio).
            'barangay' => $e->barangay,
            'purok_sitio' => $e->purok_sitio,

            // Parties. `requester_name`/`owner_name` are the names the table
            // has always rendered; the proposer_* pair makes the direction of
            // the proposal explicit for the panel.
            'requester_name' => $e->receiver?->name ?? 'Member',
            'owner_name' => $e->provider?->name ?? 'Member',
            'proposer_name' => $e->receiver?->name ?? 'Member',
            'proposer_id' => $e->receiver_id,
            'owner_id' => $e->provider_id,
            'users' => ($e->provider?->name ?? 'Member').' ↔ '.($e->receiver?->name ?? 'Member'),

            'status' => $e->frontendStatus(),
            'raw_status' => $e->status,
            'disputed' => false,

            // ── Dual-confirmation progress (read-only for admins) ──
            // Completion is member-driven only (both parties confirm via
            // POST /api/exchanges/{id}/confirm-completion); the console
            // renders this instead of a "Complete" button.
            'proposer_confirmed' => (bool) $e->proposer_confirmed,
            'owner_confirmed' => (bool) $e->owner_confirmed,
            'proposer_confirmed_at' => $e->proposer_confirmed_at?->toISOString(),
            'owner_confirmed_at' => $e->owner_confirmed_at?->toISOString(),
            'confirmation_label' => $e->confirmationLabel(),

            // No `due`/`dueCompleted` key: there is no return timer in a
            // direct barter, and an empty dash column would imply one exists.
            'updated_at' => $e->updated_at?->toISOString(),
            'created_at' => $e->created_at?->toISOString(),
            'date' => $e->created_at?->format('M j, Y') ?? '—',
            'updated_label' => $e->updated_at?->format('M j, Y') ?? '—',
        ])->values();

        return response()->json([
            'exchanges' => $rows,
            'total' => $rows->count(),
        ]);
    }

    // ------------------------------------------------------------------
    // Analytics
    // ------------------------------------------------------------------

    private function applyDateRange($query, ?string $from, ?string $to)
    {
        if ($from && strtotime($from)) {
            $query->where('created_at', '>=', $from.' 00:00:00');
        }
        if ($to && strtotime($to)) {
            $query->where('created_at', '<=', $to.' 23:59:59');
        }

        return $query;
    }

    public function analytics(Request $request)
    {
        $this->guard($request);

        $from = $request->query('from');
        $to = $request->query('to');

        $users = $this->applyDateRange(User::query(), $from, $to);
        $total = (clone $users)->count();

        $resources = $this->applyDateRange(Resource::query(), $from, $to);

        $exchanges = $this->applyDateRange(Exchange::query(), $from, $to);

        $byBarangay = Resource::with('category')
            ->when($from && strtotime((string) $from), fn ($q) => $q->where('created_at', '>=', $from.' 00:00:00'))
            ->when($to && strtotime((string) $to), fn ($q) => $q->where('created_at', '<=', $to.' 23:59:59'))
            ->get()
            ->groupBy(fn ($r) => $r->location ?: '')
            ->map(fn ($group, $location) => ['location' => $location, 'count' => $group->count()])
            ->sortByDesc('count')
            ->values();

        // Verified Trinidad residents grouped by barangay.
        $verifiedByBarangay = User::query()
            ->when($from && strtotime((string) $from), fn ($q) => $q->where('created_at', '>=', $from.' 00:00:00'))
            ->when($to && strtotime((string) $to), fn ($q) => $q->where('created_at', '<=', $to.' 23:59:59'))
            ->where('is_verified', true)
            ->where('verification_status', 'verified')
            ->whereNotNull('barangay_or_location')
            ->get()
            ->groupBy(fn ($u) => $u->barangay_or_location ?: '')
            ->map(fn ($group, $barangay) => [
                'barangay' => $barangay !== '' ? $barangay : 'Unspecified',
                'verified'  => $group->count(),
                'students'  => $group->where('student_status', true)->count(),
            ])
            ->sortByDesc('verified')
            ->values();

        return response()->json([
            'range' => [
                'from' => $from,
                'to' => $to,
            ],
                        'users' => [
                'total' => $total,
                'verified' => (clone $users)->where('is_verified', true)->count(),
                'pending' => (clone $users)->where('verification_status', 'pending')->where('is_verified', false)->count(),
                'suspended' => (clone $users)->where('account_status', 'suspended')->count(),
                'verifiedByBarangay' => $verifiedByBarangay,
            ],
            'resources' => [
                'total' => (clone $resources)->count(),
                'offers' => (clone $resources)->where('type', 'offer')->count(),
                'needs' => (clone $resources)->where('type', 'request')->count(),
                'active' => (clone $resources)->where('status', 'active')->count(),
                'removed' => (clone $resources)->whereIn('status', ['removed'])->count(),
            ],
            'exchanges' => [
                // Direct bartering is the only transaction model, so the whole
                // count is a single figure. The per-type breakdown that used to
                // sit here (freecycling / bartering / lending) is gone; keeping
                // it would have reported two permanently-zero columns.
                'bartering' => (clone $exchanges)->count(),
                'completed' => (clone $exchanges)->where('status', 'completed')->count(),
                'cancelled' => (clone $exchanges)->where('status', 'cancelled')->count(),
                'disputed' => 0,
                'byBarangay' => $byBarangay,
            ],
        ]);
    }

    // ------------------------------------------------------------------
    // Audit trail + settings
    // ------------------------------------------------------------------

    public function auditLogs(Request $request)
    {
        $this->guard($request);

                $logs = AuditLog::with('admin')->latest()
            // AuditLogsPage sends ?action=resource|user|exchange|report|settings
            ->when($request->query('action'), function ($q, $type) {
                if (in_array($type, ['user', 'resource', 'exchange', 'report', 'settings'], true)) {
                    $q->where('target_type', $type);
                }
            })
            ->take(200)->get()
            ->map(fn (AuditLog $log) => [
                'id' => $log->id,
                // Badge column shows the leading verb; description keeps the detail.
                'action' => explode(' ', (string) $log->action)[0],
                'actor' => $log->admin?->name ?? 'System',
                'admin' => $log->admin?->name ?? 'System',
                'target_type' => $log->target_type ?? 'system',
                'target_id' => $log->target_id,
                'description' => $log->action,
                'date' => $log->created_at?->format('M j, Y'),
                'time' => $log->created_at?->format('H:i'),
                'stamp' => (int) ($log->created_at?->getTimestamp() ?? 0),
            ]);

        return response()->json(['logs' => $logs, 'total' => $logs->count()]);
    }

    public function settings(Request $request)
    {
        $this->guard($request);

        $lastTouch = AdminSetting::query()
            ->whereNotNull('updated_by')
            ->latest('updated_at')
            ->first();

        return response()->json([
            'settings' => [
                'theme' => AdminSetting::value('theme', 'light'),
                'maintenanceMode' => AdminSetting::get('maintenanceMode', false),
                'maintenanceMessage' => AdminSetting::value(
                    'maintenanceMessage',
                    'The Trinidad portal is undergoing scheduled municipal updates. Please check back soon.'
                ),
                'updated_by' => $lastTouch?->updated_by,
            ],
        ]);
    }

    public function storeSettings(Request $request)
    {
        $this->guard($request);

        $validated = $request->validate([
            'theme' => ['sometimes', 'in:light,dark'],
            'maintenanceMode' => 'boolean',
            'maintenanceMessage' => ['sometimes', 'string', 'max:500'],
        ]);

        $changed = [];
        foreach ($validated as $key => $value) {
            if ($key === 'maintenanceMode') {
                AdminSetting::put($key, (bool) $value, $request->user()->name);
            } else {
                AdminSetting::putValue($key, $value, $request->user()->name);
            }
            $changed[] = $key;
        }

                if ($changed !== []) {
            $this->logAdminAction(
                $request,
                'Updated settings — '.implode(', ', $changed),
                'settings',
            );
        }

        return $this->settings($request);
    }

    public function clearCache(Request $request)
    {
        $this->guard($request);
        Artisan::call('optimize:clear');
        $this->logAdminAction($request, 'Cleared application cache', 'settings');

        return response()->json(['message' => 'Application cache cleared.']);
    }

    public function backup(Request $request): StreamedResponse
    {
        $this->guard($request);
        abort_unless(config('database.default') === 'mysql', 422, 'Database backup is configured for MySQL only.');

        $binary = trim((string) shell_exec('command -v mysqldump'));
        abort_if($binary === '', 503, 'mysqldump is not installed on the server.');

        $filename = 'cblrep-trinidad-backup-'.now()->format('Y-m-d-His').'.sql';
        $this->logAdminAction($request, 'Downloaded database backup', 'settings');

        return response()->streamDownload(function () use ($binary): void {
            $command = implode(' ', [
                escapeshellarg($binary),
                '--host='.escapeshellarg((string) config('database.connections.mysql.host')),
                '--port='.escapeshellarg((string) config('database.connections.mysql.port')),
                '--user='.escapeshellarg((string) config('database.connections.mysql.username')),
                '--password='.escapeshellarg((string) config('database.connections.mysql.password')),
                escapeshellarg((string) config('database.connections.mysql.database')),
            ]);
            passthru($command);
        }, $filename, ['Content-Type' => 'application/sql']);
    }
}
