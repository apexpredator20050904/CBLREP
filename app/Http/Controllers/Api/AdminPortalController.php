<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdminSetting;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\SystemLog;
use App\Models\TimebankTransaction;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Admin portal endpoints backing src/admin/* pages.
 * Every handler enforces the admin role guard.
 */
class AdminPortalController extends Controller
{
    private function guard(Request $request): void
    {
        abort_unless($request->user()?->role === 'admin', 403, 'Unauthorized. Admin access required.');
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

        $users = $query->get()->map(fn (User $u) => [
            'id' => $u->id,
            'name' => $u->name,
            'fullName' => $u->name,
            'email' => $u->email,
            'role' => $u->isAdmin() ? 'System Administrator' : 'General Member',
            'raw_role' => $u->role,
            'verification_status' => $u->verificationStatusLabel(),
            'account_status' => $u->accountStatusLabel(),
            'is_verified' => (bool) $u->is_verified,
            'time_bank_credits' => (float) $u->time_bank_credits,
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
                $user->save();
                $logAction = 'Verified member '.$user->name;
                break;

            case 'reject':
                if ($reason === '') {
                    abort(422, 'A rejection reason is required.');
                }
                $user->verification_status = 'rejected';
                $user->save();
                $logAction = 'Rejected verification of '.$user->name.' — '.$reason;
                break;

            case 'request-info':
                if ($reason === '') {
                    abort(422, 'Describe the information needed.');
                }
                $logAction = 'Verification info requested from '.$user->name.' — '.$reason;
                break;

            case 'suspend':
                $user->account_status = 'suspended';
                if ($reason !== '') {
                    $user->admin_note = $reason;
                }
                $user->save();
                $logAction = 'Suspended member '.$user->name.($reason !== '' ? ' — '.$reason : '');
                break;

            case 'reactivate':
                $user->account_status = 'active';
                $user->save();
                $logAction = 'Reactivated member '.$user->name;
                break;

            default:
                abort(422, 'Unsupported action.');
        }

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => $logAction ?? ucfirst($action).' recorded for '.$user->name,
            'target_type' => 'user',
            'target_id' => $user->id,
        ]);

        return response()->json([
            'message' => 'User '.$action.' successful.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
    }

    public function verification(Request $request)
    {
        $this->guard($request);

        $pending = User::where('is_verified', false)
            ->whereIn('verification_status', ['pending'])
            ->where('role', '!=', 'admin')
            ->latest()
            ->get()
            ->map(fn (User $u) => [
                'id' => $u->id,
                'fullName' => $u->name,
                'email' => $u->email,
                'barangay' => $u->barangay_or_location,
                'role' => 'General Member',
                'requested_at' => $u->created_at?->diffForHumans(),
            ])
            ->values();

        $decided = SystemLog::with('admin')
            ->where('target_type', 'user')
            ->where(function ($q) {
                $q->where('action', 'like', 'Verified%')
                    ->orWhere('action', 'like', 'Rejected%')
                    ->orWhere('action', 'like', 'Verification info requested%');
            })
            ->latest()
            ->take(25)
            ->get()
            ->map(fn (SystemLog $log) => [
                'id' => $log->id,
                'action' => $this->decisionLabel($log->action),
                'description' => $log->action,
                'date' => $log->created_at?->format('M j, Y'),
                'time' => $log->created_at?->format('H:i'),
            ]);

        return response()->json(['pending' => $pending, 'decided' => $decided]);
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
                'role' => $user->isAdmin() ? 'System Administrator' : 'General Member',
            ],
            'listings' => Resource::where('user_id', $user->id)->latest()->take(20)
                ->get(['id', 'title', 'status', 'is_active'])->toArray(),
            'tbTransactions' => TimebankTransaction::where(function ($q) use ($email) {
                $q->where('provider_email', $email)->orWhere('requester_email', $email);
            })->latest()->take(20)
                ->get(['id', 'service_title', 'status', 'credits_transferred'])->toArray(),
            // Report authorship is anonymous in this system by design.
            'reportsFiledBy' => [],
            'auditsMentioning' => SystemLog::where('target_type', 'user')
                ->where('target_id', $user->id)->latest()->take(10)
                ->get(['id', 'action'])
                ->map(fn (SystemLog $log) => [
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
        return match ($r->status ?? ($r->is_active ? 'active' : 'closed')) {
            'active' => 'Active',
            'pending' => 'Pending',
            'flagged' => 'Flagged',
            'hidden' => 'Hidden',
            'removed' => 'Removed',
            default => ucfirst((string) $r->status),
        };
    }

    private function resourceRow(Resource $r): array
    {
        return [
            'id' => $r->id,
            'title' => $r->title,
            'name' => $r->title,               // AdminMapPage reads r.name
            'type' => ucfirst($r->type ?? 'offer'),
            'category' => $r->category?->name ?? 'Tools',
            'exchange_type' => $r->exchange_type ?? 'Lend',
            'owner' => $r->user?->name ?? 'Member',
            'user' => ['id' => $r->user?->id, 'name' => $r->user?->name ?? 'Member'],
            'status' => $r->status ?? ($r->is_active ? 'active' : 'closed'),
            'admin_status' => $this->adminStatusLabel($r),
            'location' => $r->location,
            'lat' => $r->latitude,
            'lng' => $r->longitude,
            'created_at' => $r->created_at?->format('M j, Y'),
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

        $validated = $request->validate([
            'action' => 'required|in:approve,flag,hide,remove,restore',
            'reason' => 'nullable|string|max:1000',
        ]);

        $action = $validated['action'];
        $reason = trim((string) ($validated['reason'] ?? ''));

        if (in_array($action, ['remove', 'hide'], true) && $reason === '') {
            return response()->json([
                'message' => 'A reason is required for moderation actions.',
            ], 422);
        }

        $resource = Resource::findOrFail($id);

        [$newStatus, $isActive] = match ($action) {
            'approve', 'restore' => ['active', true],
            'flag' => ['flagged', false],
            'hide' => ['hidden', false],
            'remove' => ['removed', false],
        };

        $resource->update(['status' => $newStatus, 'is_active' => $isActive]);

        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => ucfirst($action).'d listing "'.$resource->title.'"'
                .($reason !== '' ? ' — '.$reason : ''),
            'target_type' => 'resource',
            'target_id' => $resource->id,
        ]);

        return response()->json([
            'message' => 'Listing '.$action.'d successfully.',
            'resource' => $this->resourceRow($resource),
        ]);
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

        $type = $request->query('type', 'all');
        $statusFilter = $request->query('status', 'all');

        // Frontend type tabs -> exchange_type column values.
        $typeMap = [
            'freecycling' => 'freecycle',
            'bartering' => 'barter',
            'lending' => 'lending',
            'timebank' => 'time_banking',
        ];

        // Status select on ExchangesPage ('cancel' tab) -> DB statuses.
        $statusMap = [
            'pending' => 'pending',
            'active' => 'accepted',
            'completed' => 'completed',
            'cancel' => 'cancelled',
        ];

        $query = Exchange::with(['resource', 'provider', 'receiver'])->latest();

        if ($mappedType = $typeMap[$type] ?? null) {
            $query->where('exchange_type', $mappedType);
        }
        if ($mappedStatus = $statusMap[$statusFilter] ?? null) {
            $query->where('status', $mappedStatus);
        }

        $rows = $query->get()->map(fn (Exchange $e) => [
            'transaction_id' => 'EX-'.str_pad((string) $e->id, 5, '0', STR_PAD_LEFT),
            'exchange_type' => $e->frontendType(),
            'users' => ($e->provider?->name ?? 'Member').' ↔ '.($e->receiver?->name ?? 'Member'),
            'provider' => $e->provider?->name ?? 'Member',
            'receiver' => $e->receiver?->name ?? 'Member',
            'resource' => $e->resource?->title ?? 'Resource Exchange',
            'disputed' => false,
            'status' => $e->frontendStatus(),
            'credits' => (float) ($e->credits_exchanged ?? 0),
            'date' => $e->created_at?->format('M j, Y') ?? '—',
        ])->values();

        return response()->json(['exchanges' => $rows, 'total' => $rows->count()]);
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
        $typeCounts = (clone $exchanges)
            ->selectRaw('exchange_type, COUNT(*) as count')
            ->groupBy('exchange_type')
            ->pluck('count', 'exchange_type');

        $byBarangay = Resource::with('category')
            ->when($from && strtotime((string) $from), fn ($q) => $q->where('created_at', '>=', $from.' 00:00:00'))
            ->when($to && strtotime((string) $to), fn ($q) => $q->where('created_at', '<=', $to.' 23:59:59'))
            ->get()
            ->groupBy(fn ($r) => $r->location ?: '')
            ->map(fn ($group, $location) => ['location' => $location, 'count' => $group->count()])
            ->sortByDesc('count')
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
            ],
            'resources' => [
                'total' => (clone $resources)->count(),
                'offers' => (clone $resources)->where('type', 'offer')->count(),
                'needs' => (clone $resources)->where('type', 'request')->count(),
                'active' => (clone $resources)->where('status', 'active')->count(),
                'removed' => (clone $resources)->whereIn('status', ['removed'])->count(),
            ],
            'exchanges' => [
                'freecycling' => (int) ($typeCounts['freecycle'] ?? 0),
                'bartering' => (int) ($typeCounts['barter'] ?? 0),
                'lending' => (int) ($typeCounts['lending'] ?? 0),
                'timeBanking' => (int) ($typeCounts['time_banking'] ?? 0),
                'completed' => (clone $exchanges)->where('status', 'completed')->count(),
                'cancelled' => (clone $exchanges)->where('status', 'cancelled')->count(),
                'disputed' => 0,
                'byBarangay' => $byBarangay,
            ],
        ]);
    }

    /**
     * CSV download — the <a href> can't send headers, so auth is via ?token=.
     */
    public function exportAnalytics(Request $request)
    {
        $token = \Laravel\Sanctum\PersonalAccessToken::findToken(
            (string) $request->query('token'),
        );
        $admin = $token?->tokenable;

        abort_if(
            ! $admin || ! ($admin instanceof User) || $admin->role !== 'admin',
            401,
            'A valid admin token is required for this export.',
        );

        $analyticsRequest = new Request([
            'from' => $request->query('from'),
            'to' => $request->query('to'),
        ]);
        $analyticsRequest->setUserResolver(fn () => $admin);

        $data = json_decode(json_encode($this->analytics($analyticsRequest)->getData(true)), true);

        $lines = [['Section', 'Metric', 'Count']];
        foreach (['users', 'resources'] as $section) {
            foreach ($data[$section] as $metric => $count) {
                if (! is_array($count)) {
                    $lines[] = [ucfirst($section), ucfirst((string) $metric), $count];
                }
            }
        }
        foreach ($data['exchanges'] as $metric => $value) {
            if ($metric === 'byBarangay') {
                foreach ($value as $row) {
                    $lines[] = ['Resources by Barangay', $row['location'] !== '' ? $row['location'] : 'Unspecified', $row['count']];
                }
                continue;
            }
            $lines[] = ['Exchanges', ucfirst(preg_replace('/([a-z])([A-Z])/', '$1 $2', (string) $metric)), $value];
        }

        $csv = implode("\n", array_map(
            fn ($row) => implode(',', array_map(fn ($cell) => '"'.str_replace('"', '""', (string) $cell).'"', $row)),
            $lines,
        ));

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="cblrep-analytics.csv"',
        ]);
    }

    // ------------------------------------------------------------------
    // Admin Time-Bank oversight (read-only ledger for admin/TimeBankPage)
    // ------------------------------------------------------------------

    public function adminTimebank(Request $request)
    {
        $this->guard($request);

        $totals = [
            'creditsEarned' => (float) TimebankTransaction::where('status', TimebankTransaction::STATUS_COMPLETED)
                ->sum('credits_transferred'),
            'creditsSpent' => (float) TimebankTransaction::where('status', TimebankTransaction::STATUS_COMPLETED)
                ->sum('credits_transferred'),
            'active' => TimebankTransaction::whereIn('status', [
                TimebankTransaction::STATUS_ACCEPTED,
                TimebankTransaction::STATUS_IN_PROGRESS,
            ])->count(),
            'pendingConfirmations' => TimebankTransaction::where('status', TimebankTransaction::STATUS_AWAITING_CONFIRMATION)->count(),
            'completed' => TimebankTransaction::where('status', TimebankTransaction::STATUS_COMPLETED)->count(),
            'disputed' => 0,
        ];

        $transactions = TimebankTransaction::query()->latest()->get()
            ->map(fn (TimebankTransaction $t) => [
                'transaction_id' => 'TB-'.str_pad((string) $t->id, 5, '0', STR_PAD_LEFT),
                'service' => $t->service_title,
                'provider' => $t->provider_name,
                'requester' => $t->requester_name,
                'hours_requested' => (float) $t->requested_hours,
                'hours_completed' => (float) $t->hours_completed,
                'credits' => ((float) $t->credits_transferred) ?: null,
                'status' => $t->status,
                'disputed' => false,
                'confirmation_status' => $t->confirmation_status,
                'created' => $t->created_at?->format('M j, Y'),
            ])->values();

        $balances = User::orderBy('name')->get()
            ->map(fn (User $u) => [
                'name' => $u->name,
                'email' => $u->email,
                'time_credit_balance' => round((float) $u->time_bank_credits, 2),
            ])->values();

        return response()->json([
            'totals' => $totals,
            'transactions' => $transactions,
            'balances' => $balances,
        ]);
    }

    // ------------------------------------------------------------------
    // Audit trail + settings
    // ------------------------------------------------------------------

    public function auditLogs(Request $request)
    {
        $this->guard($request);

        $logs = SystemLog::with('admin')->latest()
            // AuditLogsPage sends ?action=resource|user|exchange|report|settings
            ->when($request->query('action'), function ($q, $type) {
                if (in_array($type, ['user', 'resource', 'exchange', 'report', 'settings'], true)) {
                    $q->where('target_type', $type);
                }
            })
            ->take(200)->get()
            ->map(fn (SystemLog $log) => [
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
                'autoApproveListings' => AdminSetting::get('autoApproveListings', true),
                'requireProfileVerification' => AdminSetting::get('requireProfileVerification', false),
                'maintenanceMode' => AdminSetting::get('maintenanceMode', false),
                'updated_by' => $lastTouch?->updated_by,
            ],
        ]);
    }

    public function storeSettings(Request $request)
    {
        $this->guard($request);

        $validated = $request->validate([
            'autoApproveListings' => 'boolean',
            'requireProfileVerification' => 'boolean',
            'maintenanceMode' => 'boolean',
        ]);

        $changed = [];
        foreach ($validated as $key => $value) {
            AdminSetting::put($key, (bool) $value, $request->user()->name);
            $changed[] = $key.':'.($value ? 'on' : 'off');
        }

        if ($changed !== []) {
            SystemLog::create([
                'admin_id' => $request->user()->id,
                'action' => 'Updated settings — '.implode(', ', $changed),
                'target_type' => 'settings',
            ]);
        }

        return $this->settings($request);
    }
}
