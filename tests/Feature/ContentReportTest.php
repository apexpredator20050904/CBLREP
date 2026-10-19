<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Report;
use App\Models\Resource;
use App\Models\User;
use Tests\TestCase;

/**
 * Community safety reports — members flagging malicious listings and accounts.
 *
 * The contract these tests pin down:
 *   - reporting is authenticated (a report is a statement by a named member),
 *   - the reason / target vocabularies are closed, so the moderation queue can
 *     group reports without a free-text mess,
 *   - a report never removes anything on its own, but a listing that collects
 *     enough DISTINCT reports is pulled out of the feed for a moderator,
 *   - a member cannot report themselves, their own listing, or the same
 *     target twice, and
 *   - only an administrator can read or resolve the queue.
 */
class ContentReportTest extends TestCase
{
    private function member(string $name = 'Reporter'): User
    {
        return User::create([
            'name' => $name,
            'email' => strtolower($name).'-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    /**
     * The one account the admin middleware lets through.
     *
     * The admin area is a single-account lockdown keyed on the Super
     * Administrator's e-mail, and the real account has enrolled in TOTP —
     * a session-auth test token can never satisfy that gate, so the second
     * factor is switched off inside the transaction (rolled back afterwards).
     */
    private function admin(): User
    {
        $admin = User::where('email', 'admin@cblrep.ph')->first();

        if (! $admin) {
            $admin = User::create([
                'name' => 'Super Admin',
                'email' => 'admin@cblrep.ph',
                'password' => bcrypt('secret1234'),
                'role' => 'super_admin',
                'barangay' => 'Poblacion',
                'barangay_or_location' => 'Poblacion',
                'purok_sitio' => 'Purok 1',
            ]);
        }

        $admin->forceFill([
            'two_factor_enabled' => false,
            'two_factor_secret' => null,
            'two_factor_confirmed_at' => null,
        ])->save();

        return $admin;
    }

    /** A listing owned by $owner. */
    private function listing(User $owner, string $title = 'Item for sale'): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => $title,
            'description' => 'A perfectly normal item.',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    // ------------------------------------------------------------------
    // Authentication & validation
    // ------------------------------------------------------------------

    public function test_the_report_endpoint_requires_authentication(): void
    {
        $listing = $this->listing($this->member('Owner'));

        $this->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertUnauthorized();

        $this->assertSame(0, Report::count(), 'An unauthenticated call must not file a report.');
    }

    public function test_the_reason_vocabulary_is_closed(): void
    {
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'because_i_said_so',
        ])->assertStatus(422);

        $this->assertSame(0, Report::count());
    }

    public function test_the_reportable_type_vocabulary_is_closed(): void
    {
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'resource',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertStatus(422);

        $this->assertSame(0, Report::count());
    }

    public function test_a_report_needs_a_target_and_a_reason(): void
    {
        $reporter = $this->member();

        $this->actingAs($reporter)->postJson('/api/reports', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['reportable_type', 'reportable_id', 'reason']);
    }

    // ------------------------------------------------------------------
    // Filing a report
    // ------------------------------------------------------------------

    public function test_a_member_can_report_a_listing(): void
    {
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $response = $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
            'description' => 'Asked for a down payment over chat.',
        ]);

        $response->assertCreated()
            ->assertJsonPath('report.reportable_type', 'listing')
            ->assertJsonPath('report.reportable_id', $listing->id)
            ->assertJsonPath('report.reason', 'scam')
            ->assertJsonPath('report.status', 'pending');

        // The row really is in the database, with the reporter recorded.
        $this->assertSame(1, Report::count());
        $row = Report::first();
        $this->assertSame($reporter->id, $row->reporter_id);
        $this->assertSame('listing', $row->reportable_type);
        $this->assertSame($listing->id, $row->reportable_id);
        $this->assertSame('scam', $row->reason);
        $this->assertSame('Asked for a down payment over chat.', $row->description);
        $this->assertSame('pending', $row->status);
    }

    public function test_a_member_can_report_another_member(): void
    {
        $reporter = $this->member();
        $target = $this->member('Troublemaker');

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'user',
            'reportable_id' => $target->id,
            'reason' => 'harassment',
        ])->assertCreated()
            ->assertJsonPath('report.reportable_type', 'user')
            ->assertJsonPath('report.reason', 'harassment');

        $this->assertSame(1, Report::count());
    }

    public function test_the_description_is_optional(): void
    {
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'other',
        ])->assertCreated();

        $this->assertNull(Report::first()->description);
    }

    public function test_reporting_a_listing_that_no_longer_exists_is_a_404(): void
    {
        $reporter = $this->member();

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => 99999999,
            'reason' => 'scam',
        ])->assertStatus(404);

        $this->assertSame(0, Report::count());
    }

    public function test_reporting_your_own_listing_is_refused(): void
    {
        $member = $this->member();
        $listing = $this->listing($member);

        $this->actingAs($member)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertStatus(422);

        $this->assertSame(0, Report::count());
    }

    public function test_reporting_yourself_is_refused(): void
    {
        $member = $this->member();

        $this->actingAs($member)->postJson('/api/reports', [
            'reportable_type' => 'user',
            'reportable_id' => $member->id,
            'reason' => 'harassment',
        ])->assertStatus(422);

        $this->assertSame(0, Report::count());
    }

    public function test_a_duplicate_pending_report_is_refused(): void
    {
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $payload = [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ];

        $this->actingAs($reporter)->postJson('/api/reports', $payload)->assertCreated();
        $this->actingAs($reporter)->postJson('/api/reports', $payload)->assertStatus(409);

        $this->assertSame(1, Report::count(), 'The duplicate must not be recorded.');
    }

    public function test_a_member_can_read_their_own_reports(): void
    {
        $reporter = $this->member();
        $other = $this->member('Other');
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertCreated();

        $response = $this->actingAs($reporter)->getJson('/api/reports/mine')->assertOk();

        $this->assertCount(1, $response->json('reports'));
        $this->assertSame($listing->id, $response->json('reports.0.reportable_id'));

        // Another member's history is not readable through this endpoint.
        $this->actingAs($other)->getJson('/api/reports/mine')
            ->assertOk()
            ->assertJsonCount(0, 'reports');
    }

    // ------------------------------------------------------------------
    // Auto-flagging
    // ------------------------------------------------------------------

    public function test_a_listing_is_auto_flagged_after_enough_distinct_reports(): void
    {
        $listing = $this->listing($this->member('Owner'));

        for ($i = 0; $i < Report::AUTO_FLAG_THRESHOLD - 1; $i++) {
            $this->actingAs($this->member('Reporter '.$i))->postJson('/api/reports', [
                'reportable_type' => 'listing',
                'reportable_id' => $listing->id,
                'reason' => 'scam',
            ])->assertCreated();
        }

        $listing->refresh();
        $this->assertSame('active', $listing->statusKey(), 'Two reports must not hide the listing.');
        $this->assertTrue($listing->is_active);

        // The third distinct member tips it over the threshold.
        $this->actingAs($this->member('Reporter last'))->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertCreated()->assertJsonPath('listing_flagged', true);

        $listing->refresh();
        $this->assertSame('flagged', $listing->statusKey());
        $this->assertFalse($listing->is_active);
    }

    public function test_a_flagged_listing_leaves_the_public_feed(): void
    {
        $listing = $this->listing($this->member('Owner'), 'ZZREPORTABLE '.uniqid());

        for ($i = 0; $i < Report::AUTO_FLAG_THRESHOLD; $i++) {
            $this->actingAs($this->member('Reporter '.$i))->postJson('/api/reports', [
                'reportable_type' => 'listing',
                'reportable_id' => $listing->id,
                'reason' => 'scam',
            ])->assertCreated();
        }

        $ids = array_column(
            $this->getJson('/api/listings?per_page=100')->assertOk()->json('listings'),
            'id'
        );

        $this->assertNotContains($listing->id, $ids, 'A flagged listing is not public.');
    }

    public function test_the_same_member_reporting_twice_does_not_trip_the_threshold(): void
    {
        $listing = $this->listing($this->member('Owner'));
        $reporter = $this->member('Persistent');

        $payload = [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ];

        $this->actingAs($reporter)->postJson('/api/reports', $payload)->assertCreated();
        // The second attempt is a 409 — but even if it had gone through, one
        // member is one signal, not three.
        $this->actingAs($reporter)->postJson('/api/reports', $payload)->assertStatus(409);

        $listing->refresh();
        $this->assertSame('active', $listing->statusKey());
    }

    public function test_reporting_a_member_never_flags_anything(): void
    {
        $target = $this->member('Troublemaker');

        for ($i = 0; $i < Report::AUTO_FLAG_THRESHOLD + 2; $i++) {
            $this->actingAs($this->member('Reporter '.$i))->postJson('/api/reports', [
                'reportable_type' => 'user',
                'reportable_id' => $target->id,
                'reason' => 'harassment',
            ])->assertCreated();
        }

        $target->refresh();
        $this->assertSame('user', $target->role, 'An account is never auto-flagged by reports.');
        $this->assertTrue($target->is_verified === false);
    }

    // ------------------------------------------------------------------
    // The moderation queue
    // ------------------------------------------------------------------

    public function test_only_an_administrator_can_read_the_queue(): void
    {
        $member = $this->member();

        $this->actingAs($member)->getJson('/api/admin/safety-reports')->assertForbidden();
        $this->actingAs($member)->patchJson('/api/admin/safety-reports/1', [
            'status' => 'reviewed',
        ])->assertForbidden();
    }

    public function test_an_administrator_can_read_and_resolve_a_report(): void
    {
        $admin = $this->admin();
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'counterfeit',
        ])->assertCreated();

        $queue = $this->actingAs($admin)->getJson('/api/admin/safety-reports')->assertOk();
        $this->assertGreaterThanOrEqual(1, $queue->json('total'));
        $this->assertNotNull(
            collect($queue->json('reports'))->firstWhere('reason', 'counterfeit'),
            'The filed report must be in the queue.'
        );

        $report = Report::where('reason', 'counterfeit')->latest()->first();

        $this->actingAs($admin)->patchJson("/api/admin/safety-reports/{$report->id}", [
            'status' => 'action_taken',
            'resolution_note' => 'Listing removed and the member warned.',
        ])->assertOk()->assertJsonPath('report.status', 'action_taken');

        $report->refresh();
        $this->assertSame('action_taken', $report->status);
        $this->assertSame($admin->id, $report->reviewed_by);
        $this->assertNotNull($report->reviewed_at);
    }

    public function test_the_queue_can_be_filtered_by_status(): void
    {
        $admin = $this->admin();
        $reporter = $this->member();
        $listing = $this->listing($this->member('Owner'));

        $this->actingAs($reporter)->postJson('/api/reports', [
            'reportable_type' => 'listing',
            'reportable_id' => $listing->id,
            'reason' => 'scam',
        ])->assertCreated();

        $report = Report::latest()->first();
        $report->update(['status' => Report::STATUS_REVIEWED]);

        $pending = $this->actingAs($admin)
            ->getJson('/api/admin/safety-reports?status=pending')->assertOk();
        $reviewed = $this->actingAs($admin)
            ->getJson('/api/admin/safety-reports?status=reviewed')->assertOk();

        $this->assertSame(
            [],
            collect($pending->json('reports'))->pluck('id')->intersect([$report->id])->values()->all(),
            'A reviewed report must not show in the pending queue.'
        );
        $this->assertNotEmpty(
            collect($reviewed->json('reports'))->pluck('id')->intersect([$report->id])->values()->all(),
            'A reviewed report must show in the reviewed queue.'
        );
    }
}
