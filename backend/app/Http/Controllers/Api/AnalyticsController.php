<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\Exchange;
use App\Models\Resource;
use App\Models\User;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Throwable;

/**
 * Municipal analytics reporting for the CBLREP admin portal.
 *
 * Two binary exports sit behind the `admin` middleware:
 *
 *   GET /api/admin/analytics/export/csv  → exportCsv()  text/csv stream
 *   GET /api/admin/analytics/export/pdf  → exportPdf()  application/pdf
 *
 * Both share `metrics()`, so the CSV and the PDF can never disagree about the
 * numbers, and both honour the optional ?from=&to= window used by the
 * Analytics page's date range filter. Every export is written to the immutable
 * audit log with its resolved period, since a downloaded report is a
 * disclosure of aggregate community data.
 */
class AnalyticsController extends Controller
{
    /** Barangays that make up the municipality of Trinidad, Bohol. */
    private const TRINIDAD_BARANGAYS = \App\Support\Barangays::ALL;

    // ------------------------------------------------------------------
    // GET /api/admin/analytics/export/csv
    // ------------------------------------------------------------------

    /**
     * Stream the active-system metrics as a CSV file.
     *
     * Rows are written to an in-memory handle and handed to the response in
     * one piece, which keeps the memory cost flat without writing outside the
     * response object. Cells are quoted and embedded quotes doubled per
     * RFC 4180, and a UTF-8 BOM is prepended so Excel renders names such as
     * "Sto. Niño" correctly instead of mojibake.
     */
    public function exportCsv(Request $request): Response
    {
        [$from, $to] = $this->period($request);
        $metrics = $this->metrics($from, $to);

        $this->logExport($request, 'Exported analytics CSV', $from, $to);

        $filename = $this->filename('cblrep-trinidad-analytics', 'csv', $from, $to);

        $handle = fopen('php://temp', 'r+');
        if ($handle === false) {
            abort(500, 'Unable to open the CSV output stream.');
        }

        // Byte-order mark so desktop Excel detects UTF-8 automatically.
        fwrite($handle, "\xEF\xBB\xBF");
        fputcsv($handle, ['Section', 'Metric', 'Barangay', 'Count']);

        foreach ($metrics['summary'] as $row) {
            fputcsv($handle, ['Summary', $row['label'], 'All', $row['value']]);
        }

        foreach ($metrics['exchanges'] as $row) {
            fputcsv($handle, ['Exchanges', $row['label'], 'All', $row['value']]);
        }

        foreach ($metrics['byBarangay'] as $row) {
            fputcsv($handle, ['Verified Residents', 'Verified residents', $row['barangay'], $row['verified']]);
            fputcsv($handle, ['Verified Residents', 'Student residents', $row['barangay'], $row['students']]);
        }

        rewind($handle);
        $csv = (string) stream_get_contents($handle);
        fclose($handle);

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
            'Cache-Control' => 'no-store, no-cache, must-revalidate',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }

    // ------------------------------------------------------------------
    // GET /api/admin/analytics/export/pdf
    // ------------------------------------------------------------------

    /**
     * Render the same metrics as a real, downloadable PDF report.
     *
     * dompdf produces an actual application/pdf binary rather than a
     * print-to-PDF HTML shim, so the file opens directly in any viewer and
     * the Content-Disposition filename matches the bytes sent to the browser.
     */
    public function exportPdf(Request $request): Response
    {
        [$from, $to] = $this->period($request);
        $metrics = $this->metrics($from, $to);

        $this->logExport($request, 'Exported analytics PDF', $from, $to);

        $filename = $this->filename('cblrep-trinidad-analytics-report', 'pdf', $from, $to);

        return Pdf::loadView('admin.analytics-report', $metrics)
            ->setPaper('a4', 'portrait')
            ->download($filename);
    }

    // ------------------------------------------------------------------
    // Shared helpers
    // ------------------------------------------------------------------

    /**
     * Build every figure both exports render, so the CSV and the PDF can
     * never disagree about the numbers.
     *
     * "Active" means a listing whose is_active flag is on and whose status
     * has not been moderated away; completed exchanges are the ones members
     * closed out. Every count is constrained to the requested window.
     */
    private function metrics(?string $from, ?string $to): array
    {
        $inRange = function ($query) use ($from, $to) {
            if ($from) {
                $query->where('created_at', '>=', $from.' 00:00:00');
            }
            if ($to) {
                $query->where('created_at', '<=', $to.' 23:59:59');
            }

            return $query;
        };

        $residents = $inRange(User::query()->where('role', User::ROLE_USER));
        $verified = (clone $residents)->where('is_verified', true);

        $activeListings = $inRange(Resource::query())
            ->where('is_active', true)
            ->where('status', 'active');

        $exchanges = $inRange(Exchange::query());

        $byBarangay = $this->residentsByBarangay($verified);

        return [
            'generatedAt' => now()->format('M j, Y g:i A'),
            'period' => [
                'from' => $from ?? 'All time',
                'to' => $to ?? 'Present',
            ],
            'summary' => [
                ['label' => 'Total registered residents', 'value' => (clone $residents)->count()],
                ['label' => 'Verified residents', 'value' => (clone $verified)->count()],
                ['label' => 'Active offers', 'value' => (clone $activeListings)->where('type', 'offer')->count()],
                ['label' => 'Active needs', 'value' => (clone $activeListings)->where('type', 'request')->count()],
                ['label' => 'Active listings (all)', 'value' => (clone $activeListings)->count()],
                ['label' => 'Completed exchanges', 'value' => (clone $exchanges)->where('status', 'completed')->count()],
            ],
            'exchanges' => [
                ['label' => 'Barter proposals received', 'value' => (clone $exchanges)->count()],
                ['label' => 'Barter proposals accepted', 'value' => (clone $exchanges)->where('status', Exchange::STATUS_ACCEPTED)->count()],
                ['label' => 'Barter trades completed', 'value' => (clone $exchanges)->where('status', Exchange::STATUS_COMPLETED)->count()],
                ['label' => 'Barter proposals declined', 'value' => (clone $exchanges)->whereIn('status', [Exchange::STATUS_REJECTED, Exchange::STATUS_CANCELLED])->count()],
            ],
            'byBarangay' => $byBarangay,
        ];
    }

    /**
     * Verified-resident counts per barangay.
     *
     * Every barangay in the municipality is emitted — including the ones with
     * no residents yet — so a zero-population area still surfaces in the
     * report instead of silently vanishing. Anything filed under a
     * barangay outside the list is grouped afterwards so the per-row totals
     * still reconcile with the verified-resident headline figure.
     *
     * @param  \Illuminate\Database\Eloquent\Builder  $verified
     * @return \Illuminate\Support\Collection<int, array{barangay: string, verified: int, students: int}>
     */
    private function residentsByBarangay($verified)
    {
        $grouped = $verified
            ->get(['barangay_or_location', 'student_status'])
            ->groupBy(fn ($user) => $user->barangay_or_location ?: 'Unspecified')
            ->map(fn ($group, $barangay) => [
                'barangay' => $barangay,
                'verified' => $group->count(),
                'students' => $group->where('student_status', true)->count(),
            ]);

        $known = collect(self::TRINIDAD_BARANGAYS)->map(fn ($barangay) => $grouped->get($barangay, [
            'barangay' => $barangay,
            'verified' => 0,
            'students' => 0,
        ]));

        $knownByName = $known->keyBy('barangay');

        $other = $grouped
            ->reject(fn ($row) => $knownByName->has($row['barangay']))
            ->values();

        return $known
            ->concat($other)
            ->sortByDesc('verified')
            ->values()
            ->all();
    }

    /**
     * Validate the optional ?from=&to= window.
     *
     * Unparseable input is dropped rather than rejected so a hand-edited URL
     * degrades to an all-time report instead of a 422. When `from` lands after
     * `to` the pair is swapped, so the range can never invert.
     *
     * @return array{0: ?string, 1: ?string}
     */
    private function period(Request $request): array
    {
        $from = $this->validDate($request->query('from'));
        $to = $this->validDate($request->query('to'));

        if ($from && $to && $from > $to) {
            [$from, $to] = [$to, $from];
        }

        return [$from, $to];
    }

    private function validDate(mixed $value): ?string
    {
        if (! is_string($value) || trim($value) === '') {
            return null;
        }

        $value = trim($value);

        return strtotime($value) !== false ? substr($value, 0, 10) : null;
    }

    /**
     * Filesystem-safe report name carrying the period and generation stamp,
     * e.g. cblrep-trinidad-analytics-all-time-20260929-141205.csv
     */
    private function filename(string $base, string $extension, ?string $from, ?string $to): string
    {
        $span = match (true) {
            $from && $to => $from.'-to-'.$to,
            $from => 'from-'.$from,
            $to => 'to-'.$to,
            default => 'all-time',
        };

        $safe = preg_replace('/[^A-Za-z0-9\-_]/', '', $span) ?: 'all-time';

        return sprintf('%s-%s-%s.%s', $base, $safe, now()->format('Ymd-His'), $extension);
    }

    /**
     * Record the disclosure in the immutable admin audit trail.
     *
     * A failure here is swallowed: a reporting export the administrator
     * explicitly asked for must still download if the audit write errors.
     */
    private function logExport(Request $request, string $action, ?string $from, ?string $to): void
    {
        try {
            AuditLog::record(
                $request,
                $action,
                'analytics',
                null,
                'Period: '.($from ?? 'all time').' to '.($to ?? 'present'),
            );
        } catch (Throwable) {
            // Intentionally ignored — see docblock.
        }
    }
}
