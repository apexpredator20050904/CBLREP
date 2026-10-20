<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Report;
use App\Models\Resource;
use App\Models\SystemLog;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Community safety reports — the member-facing end of the moderation loop.
 *
 * A member reports a malicious listing or a member's account; the report is
 * recorded as `pending` and a moderator decides what happens next. Reporting
 * never removes anything on its own — except that a listing which collects
 * [Report::AUTO_FLAG_THRESHOLD] distinct pending reports is pulled out of the
 * community feed and flagged for a moderator, so a live scam stops being
 * visible while it is being looked at.
 */
class ReportController extends Controller
{
    /**
     * POST /api/reports — file a report.
     *
     * Authenticated: a report is a statement by a named member, so it is
     * worthless (and abusable) without a session behind it.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            // 'listing' | 'user' — a plain discriminator, not a morph type.
            'reportable_type' => ['required', 'string', Rule::in(Report::TARGETS)],
            'reportable_id' => ['required', 'integer', 'min:1'],
            // The reason vocabulary is closed so the moderation queue can
            // group reports without a free-text mess.
            'reason' => ['required', 'string', Rule::in(Report::REASONS)],
            'description' => ['nullable', 'string', 'max:1000'],
        ]);

        $type = $validated['reportable_type'];
        $id = (int) $validated['reportable_id'];

        // Resolve the target. A report about something that no longer exists
        // is a 404, not a silent success — the member is told their action
        // could not be attached to anything.
        if ($type === Report::TARGET_LISTING) {
            $listing = Resource::find($id);
            if (! $listing) {
                return response()->json([
                    'message' => 'That listing no longer exists, so it cannot be reported.',
                ], 404);
            }
            // Your own listing is not a report.
            if ($listing->user_id === $request->user()->id) {
                return response()->json([
                    'message' => 'You cannot report your own listing.',
                ], 422);
            }
        } else {
            $member = User::find($id);
            if (! $member) {
                return response()->json([
                    'message' => 'That member no longer exists, so they cannot be reported.',
                ], 404);
            }
            // Nor is yourself.
            if ($member->id === $request->user()->id) {
                return response()->json([
                    'message' => 'You cannot report your own account.',
                ], 422);
            }
        }

        // One open report per member per target. The duplicate is rejected
        // with a 409 rather than silently swallowed, so the client can tell
        // the member their earlier report is already in the queue.
        $already = Report::where('reporter_id', $request->user()->id)
            ->where('reportable_type', $type)
            ->where('reportable_id', $id)
            ->where('status', Report::STATUS_PENDING)
            ->exists();

        if ($already) {
            return response()->json([
                'message' => 'You have already reported this. Our team is reviewing it.',
            ], 409);
        }

        $report = Report::create([
            'reporter_id' => $request->user()->id,
            'reportable_type' => $type,
            'reportable_id' => $id,
            'reason' => $validated['reason'],
            'description' => $validated['description'] ?? null,
            'status' => Report::STATUS_PENDING,
        ]);

        // A listing that keeps collecting reports is pulled out of the feed
        // for a moderator to look at. Distinct reporters only — the same
        // member reporting ten times is one signal, not ten.
        $flagged = false;
        if ($type === Report::TARGET_LISTING) {
            $flagged = $this->autoFlagIfThresholdReached($id);
        }

        // The reports table is itself the queue, but a line in the system log
        // makes the event visible to the admin dashboard without a join.
        // (The dedicated audit trail is for ADMIN state changes — the
        // moderator's verdict is recorded there instead, in update()).
        SystemLog::create([
            'admin_id' => $request->user()->id,
            'action' => 'Report filed against '.$report->subjectLabel(),
            'target_type' => 'report',
            'target_id' => $report->id,
        ]);
        return response()->json([
            'message' => 'Report received. Thank you for helping keep our community safe.',
            'report' => $report->toArray(),
            // Informational only: tells the client the listing is now being
            // held for review, so the UI can say so plainly.
            'listing_flagged' => $flagged,
        ], 201);
    }

    /**
     * GET /api/reports/mine — the member's own report history.
     *
     * Lets the app show "you already reported this" and gives a member
     * proof that their report was received.
     */
    public function mine(Request $request)
    {
        $reports = Report::where('reporter_id', $request->user()->id)
            ->latest()
            ->limit(100)
            ->get()
            ->map(fn (Report $report) => $report->toArray())
            ->values();

        return response()->json([
            'reports' => $reports,
            'total' => $reports->count(),
        ]);
    }

    /**
     * GET /api/admin/safety-reports — the moderation queue.
     *
     * The path deliberately avoids `/api/admin/reports`, which is already
     * taken by the older flagged-listing queue (VerificationReportsController).
     */
    public function index(Request $request)
    {
        abort_unless($request->user()->isAdmin(), 403, 'Unauthorized. Admin access required.');

        $status = strtolower(trim((string) $request->query('status', 'all')));
        $type = strtolower(trim((string) $request->query('type', 'all')));

        $reports = Report::query()
            ->with(['reporter', 'reviewer'])
            ->when($status !== '' && $status !== 'all', fn ($q) => $q->where('status', $status))
            ->when($type !== '' && $type !== 'all', fn ($q) => $q->where('reportable_type', $type))
            ->latest()
            ->limit(200)
            ->get()
            ->map(fn (Report $report) => array_merge($report->toArray(), [
                'reporter_name' => $report->reporter?->name ?? 'Deleted member',
                'reviewed_by_name' => $report->reviewer?->name,
            ]))
            ->values();

        return response()->json([
            'reports' => $reports,
            'total' => $reports->count(),
        ]);
    }

    /**
     * PATCH /api/admin/safety-reports/{id} — record a moderator's decision.
     *
     * `reviewed` means the moderator has looked at it; `action_taken` means
     * something was done about it. The report row is the record of that
     * decision, so it is never deleted — only advanced.
     */
    public function update(Request $request, $id)
    {
        abort_unless($request->user()->isAdmin(), 403, 'Unauthorized. Admin access required.');

        $validated = $request->validate([
            'status' => ['required', 'string', Rule::in([Report::STATUS_REVIEWED, Report::STATUS_ACTION_TAKEN])],
            'resolution_note' => ['nullable', 'string', 'max:1000'],
        ]);

        $report = Report::findOrFail($id);

        $report->update([
            'status' => $validated['status'],
            'resolution_note' => $validated['resolution_note'] ?? null,
            'reviewed_at' => now(),
            'reviewed_by' => $request->user()->id,
        ]);

        AuditLog::record(
            $request,
            'Report '.$report->id.' marked '.$report->statusLabel(),
            $report->reportable_type,
            $report->reportable_id,
            $validated['resolution_note'] ?? null,
        );

        return response()->json([
            'message' => 'Report marked '.$report->statusLabel().'.',
            'report' => $report->fresh()->toArray(),
        ]);
    }

    /**
     * Pull a listing out of the feed once enough distinct members have
     * reported it.
     *
     * The write is exactly what the admin console's `flag` action performs
     * (`status = flagged`, `is_active = false`), so a listing that trips
     * this threshold lands in the existing moderation queue with no extra
     * wiring — and a moderator can restore it if the reports turn out to be
     * unfounded.
     *
     * @return bool Whether the listing was flagged by this call.
     */
    private function autoFlagIfThresholdReached(int $listingId): bool
    {
        $listing = Resource::find($listingId);
        if (! $listing) {
            return false;
        }

        // Already held by a moderator — nothing to change, and the caller's
        // response must not claim it just happened.
        if ($listing->isModerationStatus()) {
            return false;
        }

        // Distinct reporters, not distinct rows: the same member reporting
        // the same listing ten times is one signal, not ten. `count(DISTINCT
        // reporter_id)` is written explicitly — Laravel's plain
        // `distinct()->count('column')` does NOT add the DISTINCT keyword
        // and would happily count the same member's rows separately.
        $distinctReporters = Report::pendingAgainst(Report::TARGET_LISTING, $listingId)
            ->whereNotNull('reporter_id')
            ->count(DB::raw('DISTINCT reporter_id'));

        if ($distinctReporters < Report::AUTO_FLAG_THRESHOLD) {
            return false;
        }

        $listing->update([
            'status' => Resource::FLAGGED,
            'is_active' => false,
        ]);

        return true;
    }
}
