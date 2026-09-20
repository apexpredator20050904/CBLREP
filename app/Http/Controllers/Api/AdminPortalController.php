<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdminSetting;
use App\Models\AuditLog;
use App\Models\Exchange;
use App\Models\Resource;
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

    /**
     * Centralised audit-log writer — delegates to AuditLog::record()
     * so every admin action is captured with IP + user-agent.
     */
    private function logAdminAction(Request $request, string $action, ?string $targetType = null, ?int $targetId = null, ?string $details = null): AuditLog
    {
        return AuditLog::record($request, $action, $targetType, $targetId, $details);
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
            'email' => $u->email,
            'role' => $u->isAdmin() ? 'System Administrator' : 'General Member',
            'raw_role' => $u->role,
            'verification_status' => $u->verificationStatusLabel(),
            'account_status' => $u->accountStatusLabel(),
            'is_verified' => (bool) $u->is_verified,
            'is_student' => (bool) $u->student_status,
            'student_school' => $u->student_school,
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

        return response()->json([
            'message' => 'User '.$action.' successful.',
            'user' => $user->fresh()->toFrontendArray(),
        ]);
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
                'email' => $u->email,
                'barangay' => $u->barangay_or_location,
                'is_student' => (bool) $u->student_status,
                'student_school' => $u->student_school,
                'role' => 'General Member',
                'requested_at' => $u->created_at?->diffForHumans(),
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
            'tbTransactions' => TimebankTransaction::where(function ($q) use ($email) {
                $q->where('provider_email', $email)->orWhere('requester_email', $email);
            })->latest()->take(20)
                ->get(['id', 'service_title', 'status', 'credits_transferred'])->toArray(),
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
     * Export analytics to CSV or PDF (controlled by ?fmt=csv|pdf).
     *
     * Auth is handled by the auth:sanctum + admin middleware on the route,
     * but we also accept a ?token= fallback for <a href> downloads that
     * cannot send an Authorization header.
     */
    public function exportAnalytics(Request $request)
    {
        $fmt = $request->query('fmt', 'csv');

        // Auth: prefer Sanctum bearer (middleware guarantees admin), fall
        // back to ?token= for <a href> downloads that cannot send headers.
        if (! $request->user()) {
            $token = \Laravel\Sanctum\PersonalAccessToken::findToken(
                (string) $request->query('token'),
            );
            $admin = $token?->tokenable;
            abort_if(
                ! $admin || ! ($admin instanceof User) || $admin->role !== 'admin',
                401,
                'A valid admin token is required for this export.',
            );
        } else {
            $this->guard($request);
            $admin = $request->user();
        }

        $analyticsRequest = new Request([
            'from' => $request->query('from'),
            'to'   => $request->query('to'),
        ]);
        $analyticsRequest->setUserResolver(fn () => $admin);

        $data = json_decode(json_encode($this->analytics($analyticsRequest)->getData(true)), true);

        // ---- CSV export ----
        if ($fmt === 'csv') {
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
            foreach ($data['users']['verifiedByBarangay'] ?? [] as $row) {
                $lines[] = ['Verified Residents by Barangay', $row['barangay'], $row['verified']];
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

        // ---- PDF export (print-friendly HTML) ----
        return response($this->renderAnalyticsHtml($data), 200, [
            'Content-Type' => 'text/html; charset=UTF-8',
            'Content-Disposition' => 'inline; filename="cblrep-analytics.pdf"',
        ]);
    }

    /**
     * Render a print-friendly HTML page for the analytics dashboard.
     * The browser's print-to-PDF dialog produces the final PDF.
     */
    private function renderAnalyticsHtml(array $data): string
    {
        $rows = [];
        foreach (['users', 'resources'] as $section) {
            foreach ($data[$section] ?? [] as $metric => $count) {
                if (! is_array($count)) {
                    $rows[] = '<tr><td>'.ucfirst($section).'</td><td>'.ucfirst((string) $metric).'</td><td>'.$count.'</td></tr>';
                }
            }
        }
        foreach ($data['exchanges'] ?? [] as $metric => $value) {
            if ($metric === 'byBarangay') {
                foreach ($value as $row) {
                    $rows[] = '<tr><td>Resources by Barangay</td><td>'.($row['location'] !== '' ? $row['location'] : 'Unspecified').'</td><td>'.$row['count'].'</td></tr>';
                }
                continue;
            }
            $label = ucfirst(preg_replace('/([a-z])([A-Z])/', '$1 $2', (string) $metric));
            $rows[] = '<tr><td>Exchanges</td><td>'.$label.'</td><td>'.$value.'</td></tr>';
        }
        foreach ($data['users']['verifiedByBarangay'] ?? [] as $row) {
            $rows[] = '<tr><td>Verified Residents</td><td>'.$row['barangay'].'</td><td>'.$row['verified'].'</td></tr>';
        }

        $byBarangayRows = '';
        foreach (($data['exchanges']['byBarangay'] ?? []) as $b) {
            $byBarangayRows .= '<tr><td>'.($b['location'] !== '' ? $b['location'] : 'Unspecified').'</td><td>'.$b['count'].'</td></tr>';
        }

        $verifiedRows = '';
        foreach (($data['users']['verifiedByBarangay'] ?? []) as $row) {
            $verifiedRows .= '<tr><td>'.$row['barangay'].'</td><td>'.$row['verified'].'</td><td>'.($row['students'] ?? 0).'</td></tr>';
        }

        return '<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<title>CBLREP Analytics Report</title>
<style>
  body { font-family: Arial, sans-serif; margin: 24px; color: #1b382b; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  h2 { font-size: 16px; margin-top: 24px; border-bottom: 2px solid #2d6a4f; padding-bottom: 4px; }
  table { border-collapse: collapse; width: 100%; margin-top: 8px; }
  th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; font-size: 12px; }
  th { background: #e8f0e8; font-weight: bold; }
  tr:nth-child(even) { background: #f7f7f4; }
  .footer { margin-top: 32px; font-size: 10px; color: #888; }
</style>
</head><body>
<h1>Community-Based Local Resources Exchange Portal (CBLREP)</h1>
<p>Trinidad, Bohol &middot; Analytics Report</p>
<p>Period: '.($data['range']['from'] ?? 'all time').' to '.($data['range']['to'] ?? 'now').'</p>
<h2>Summary Statistics</h2>
<table><thead><tr><th>Section</th><th>Metric</th><th>Count</th></tr></thead><tbody>'.implode('', $rows).'</tbody></table>
<h2>Resources by Barangay</h2>
<table><thead><tr><th>Barangay</th><th>Total Count</th></tr></thead><tbody>'.$byBarangayRows.'</tbody></table>
<h2>Verified Residents by Barangay</h2>
<table><thead><tr><th>Barangay</th><th>Verified Residents</th><th>Students</th></tr></thead><tbody>'.$verifiedRows.'</tbody></table>
<div class="footer">Generated by CBLREP Admin Portal &middot; '.now()->format('M j, Y g:i A').'</div>
</body></html>';
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
            $this->logAdminAction(
                $request,
                'Updated settings — '.implode(', ', $changed),
                'settings',
            );
        }

        return $this->settings($request);
    }
}
