<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Resource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * Community reports queue.
 *
 * Reports originate from members flagging listings: every resource whose
 * status is "flagged" appears as a PENDING report. Decisions are persisted
 * to storage/app/reports.json (same pattern as realtime.json) and mirrored
 * into system_logs for the audit trail.
 */
class VerificationReportsController extends Controller
{
    private function storePath(): string
    {
        return 'app/reports.json';
    }

    /** @return array<int, array<string, mixed>> */
    private function loadReports(): array
    {
        if (! Storage::exists($this->storePath())) {
            return [];
        }

        $decoded = json_decode(Storage::get($this->storePath()), true);

        return is_array($decoded) ? $decoded : [];
    }

    private function saveReports(array $reports): void
    {
        Storage::put($this->storePath(), json_encode(array_values($reports), JSON_PRETTY_PRINT));
    }

    /**
     * Make sure every flagged listing has a report entry; return id => row map.
     */
    private function syncFlaggedResources(): array
    {
        $reports = collect($this->loadReports())->keyBy('resource_id');
        $existingIds = $reports->keys()->all();

        Resource::where('status', 'flagged')
            ->whereNotIn('id', $existingIds)
            ->get()
            ->each(function (Resource $resource) use (&$reports) {
                $reports->put($resource->id, [
                    'resource_id' => $resource->id,
                    'subject_label' => 'Listing: '.$resource->title,
                    'reporter_name' => 'Community flag',
                    'reason' => Str::limit((string) $resource->description, 120, '…'),
                    'status' => 'PENDING',
                    'created_at' => now()->toIso8601String(),
                ]);
            });

        $this->saveReports($reports->values()->all());

        return $reports->all();
    }

    public function index(Request $request)
    {
        abort_unless($request->user()->role === 'admin', 403, 'Unauthorized. Admin access required.');

        $status = strtoupper($request->query('status', 'all'));

        $reports = collect($this->syncFlaggedResources())
            ->when($status !== 'all', fn ($c) => $c->where('status', $status))
            ->sortByDesc('created_at')
            ->map(fn ($row, $i) => array_merge(['id' => $row['resource_id']], $row))
            ->values();

        return response()->json([
            'reports' => $reports,
            'total' => $reports->count(),
        ]);
    }

    public function resolve(Request $request, $id)
    {
        abort_unless($request->user()->role === 'admin', 403, 'Unauthorized. Admin access required.');

        $validated = $request->validate([
            'decision' => ['required', 'in:UNDER REVIEW,RESOLVED,DISMISSED'],
            'notes' => ['required_unless:decision,UNDER REVIEW', 'nullable', 'string', 'max:1000'],
        ]);

        $decision = $validated['decision'];
        $notes = trim((string) ($validated['notes'] ?? ''));

        $reports = collect($this->syncFlaggedResources());
        $row = $reports->firstWhere('resource_id', (int) $id);
        abort_if($row === null, 404, 'Report not found.');

        $row['status'] = $decision;
        $row['resolved_at'] = now()->toIso8601String();
        $row['resolved_by'] = $request->user()->name;
        $row['notes'] = $notes;
        $reports->transform(fn ($r) => $r['resource_id'] === (int) $id ? $row : $r);
        $this->saveReports($reports->values()->all());

        // Content decision follows the verdict: dismissal restores the
        // listing, resolution keeps it down, further review stays flagged.
        $resource = Resource::find($id);
        if ($resource) {
            match ($decision) {
                'DISMISSED' => $resource->update(['status' => 'active', 'is_active' => true]),
                'RESOLVED' => $resource->update(['status' => 'removed', 'is_active' => false]),
                default => null,
            };
        }

        AuditLog::record(
            $request,
            'Report for '.$row['subject_label'].' marked '.$decision,
            'resource',
            (int) $id,
            $notes,
        );

        return response()->json([
            'message' => 'Report marked '.$decision.'.',
            'report' => array_merge(['id' => (int) $id], $row),
        ]);
    }
}
