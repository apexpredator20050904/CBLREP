<?php

namespace Tests\Feature;

use App\Models\Announcement;
use App\Models\Category;
use App\Models\DeviceToken;
use App\Models\MemberNotification;
use App\Models\Resource;
use App\Models\User;
use App\Services\NotificationService;
use App\Services\PushService;
use Tests\TestCase;

/**
 * Notification Service (Part B).
 *
 * The old behaviour: only chat produced an FCM push, the Settings toggles lived
 * only on the device and were ignored by the server, and a member was never
 * told when their verification was decided or their listing was moderated.
 *
 * These tests pin the new contract:
 *   - the in-app row is ALWAYS written (it is the source of truth), and
 *   - the push is sent only when the member's own preferences allow it, and
 *   - the push carries the right type/category/channel for deep-linking.
 */
class NotificationTest extends TestCase
{
    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private function member(string $name = 'Test Member'): User
    {
        return User::create([
            'name' => $name,
            'email' => $name.'-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    /** The one account the admin middleware lets through. */
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

        // The real admin has enrolled in TOTP; a session-auth test token can
        // never satisfy that gate. Disabling it inside the transaction (rolled
        // back afterwards) is what lets us exercise the admin endpoints.
        $admin->forceFill([
            'two_factor_enabled' => false,
            'two_factor_secret' => null,
            'two_factor_confirmed_at' => null,
        ])->save();

        return $admin;
    }

    private function listingFor(User $owner, string $title = 'A borrowed drill'): Resource
    {
        return Resource::create([
            'user_id' => $owner->id,
            'category_id' => Category::firstOrCreate(['name' => 'Tools'])->id,
            'type' => 'offer',
            'compensation_type' => 'barter',
            'title' => $title,
            'description' => 'Works fine.',
            'condition' => 'Good',
            'location' => 'Poblacion, Purok 3',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'is_active' => true,
            'status' => 'active',
        ]);
    }

    /** A PushService stand-in that records what would have been pushed. */
    private function spyPush(): PushService
    {
        return new class extends PushService
        {
            /** @var list<array<string, mixed>> */
            public array $sent = [];

            /** @var list<array<string, mixed>> */
            public array $batches = [];

            public function sendToUser(int $userId, string $title, string $body, array $data = [], ?string $channel = null): void
            {
                $this->sent[] = compact('userId', 'title', 'body', 'data', 'channel');
            }

            public function sendToTokens(array $tokens, string $title, string $body, array $data = [], ?string $channel = null): void
            {
                $this->batches[] = compact('tokens', 'title', 'body', 'data', 'channel');
            }
        };
    }

    // ------------------------------------------------------------------
    // Preference logic
    // ------------------------------------------------------------------

    public function test_a_member_without_stored_preferences_wants_every_push(): void
    {
        $member = $this->member();

        $this->assertTrue($member->wantsPush(NotificationService::CATEGORY_MESSAGES));
        $this->assertTrue($member->wantsPush(NotificationService::CATEGORY_EXCHANGES));
        $this->assertTrue($member->wantsPush(NotificationService::CATEGORY_ANNOUNCEMENTS));
        $this->assertTrue($member->wantsPush(NotificationService::CATEGORY_ACCOUNT));
    }

    public function test_the_master_switch_silences_every_category(): void
    {
        $member = $this->member();
        $member->forceFill(['notification_preferences' => ['enabled' => false]])->save();

        $this->assertFalse($member->fresh()->wantsPush(NotificationService::CATEGORY_MESSAGES));
        $this->assertFalse($member->fresh()->wantsPush(NotificationService::CATEGORY_EXCHANGES));
    }

    public function test_a_single_category_can_be_muted_without_muting_the_rest(): void
    {
        $member = $this->member();
        $member->forceFill(['notification_preferences' => ['exchanges' => false]])->save();
        $member = $member->fresh();

        $this->assertFalse($member->wantsPush(NotificationService::CATEGORY_EXCHANGES));
        $this->assertTrue($member->wantsPush(NotificationService::CATEGORY_MESSAGES),
            'Muting barter alerts must not silence chat.');
    }

    // ------------------------------------------------------------------
    // NotificationService: row always, push gated
    // ------------------------------------------------------------------

    public function test_notify_records_the_row_and_pushes_when_allowed(): void
    {
        $member = $this->member();
        $push = $this->spyPush();

        (new NotificationService($push))->notify(
            $member->id,
            NotificationService::CATEGORY_EXCHANGES,
            'exchange_request',
            'New barter proposal',
            'Someone wants your drill.',
            ['exchange_id' => 7],
        );

        $this->assertDatabaseHas('member_notifications', [
            'user_id' => $member->id,
            'type' => 'exchange_request',
        ]);

        $this->assertCount(1, $push->sent);
        $this->assertSame('cblrep_exchanges', $push->sent[0]['channel']);
        $this->assertSame('exchange_request', $push->sent[0]['data']['type']);
    }

    public function test_a_muted_category_still_records_the_row_but_does_not_push(): void
    {
        $member = $this->member();
        $member->forceFill(['notification_preferences' => ['exchanges' => false]])->save();

        $push = $this->spyPush();
        (new NotificationService($push))->notify(
            $member->id,
            NotificationService::CATEGORY_EXCHANGES,
            'exchange_update',
            'Barter accepted',
            'Your proposal moved.',
        );

        // The inbox keeps the record (nothing is lost)…
        $this->assertDatabaseHas('member_notifications', [
            'user_id' => $member->id,
            'type' => 'exchange_update',
        ]);
        // …but no push goes out.
        $this->assertCount(0, $push->sent);
    }

    public function test_an_announcement_replay_neither_duplicates_nor_re_pushes(): void
    {
        $member = $this->member();
        $announcement = Announcement::create([
            'title' => 'Barangay assembly',
            'body' => 'Meeting on Saturday.',
        ]);

        $push = $this->spyPush();
        $service = new NotificationService($push);

        $args = [
            $member->id,
            NotificationService::CATEGORY_ANNOUNCEMENTS,
            'announcement',
            'Barangay assembly',
            'Meeting on Saturday.',
            ['announcement_id' => $announcement->id],
            ['announcement_id' => $announcement->id],
        ];

        $service->notify(...$args);
        $service->notify(...$args); // replay

        $this->assertSame(
            1,
            MemberNotification::where('user_id', $member->id)
                ->where('announcement_id', $announcement->id)
                ->count(),
            'Re-sending an announcement must not duplicate the row.',
        );
        $this->assertCount(1, $push->sent, 'A replay must not push twice.');
    }

    public function test_notify_many_records_for_all_but_only_pushes_allowed_members(): void
    {
        $a = $this->member('Batch A');
        $b = $this->member('Batch B');
        $muted = $this->member('Batch Muted');
        $muted->forceFill(['notification_preferences' => ['announcements' => false]])->save();

        DeviceToken::create(['user_id' => $a->id, 'token' => 'tok-a', 'platform' => 'android']);
        DeviceToken::create(['user_id' => $b->id, 'token' => 'tok-b', 'platform' => 'android']);
        DeviceToken::create(['user_id' => $muted->id, 'token' => 'tok-muted', 'platform' => 'android']);

        $announcement = Announcement::create([
            'title' => 'Water interruption',
            'body' => 'No water on Sunday.',
        ]);

        $push = $this->spyPush();
        $service = new NotificationService($push);

        $created = $service->notifyMany(
            [$a->id, $b->id, $muted->id],
            NotificationService::CATEGORY_ANNOUNCEMENTS,
            'announcement',
            $announcement->title,
            $announcement->body,
            ['announcement_id' => $announcement->id],
            ['announcement_id' => $announcement->id],
        );

        $this->assertSame(3, $created, 'Every recipient keeps an inbox record.');
        $this->assertSame(3, MemberNotification::where('announcement_id', $announcement->id)->count());

        // One batched send, and the muted member's device is excluded.
        $this->assertCount(1, $push->batches);
        $tokens = $push->batches[0]['tokens'];
        $this->assertContains('tok-a', $tokens);
        $this->assertContains('tok-b', $tokens);
        $this->assertNotContains('tok-muted', $tokens);
        $this->assertSame('cblrep_announcements', $push->batches[0]['channel']);

        // Replaying the broadcast must not create rows or push again.
        $again = $service->notifyMany(
            [$a->id, $b->id, $muted->id],
            NotificationService::CATEGORY_ANNOUNCEMENTS,
            'announcement',
            $announcement->title,
            $announcement->body,
            ['announcement_id' => $announcement->id],
            ['announcement_id' => $announcement->id],
        );

        $this->assertSame(0, $again);
        $this->assertCount(1, $push->batches, 'A replay must not push again.');
    }

    // ------------------------------------------------------------------
    // Verification decisions (the previously silent gap)
    // ------------------------------------------------------------------

    public function test_verifying_a_member_notifies_them(): void
    {
        $member = $this->member('Ana Member');
        $admin = $this->admin();

        $this->actingAs($admin)
            ->postJson("/api/admin/users/{$member->id}/verify", ['reason' => 'Valid ID seen'])
            ->assertOk();

        $this->assertDatabaseHas('member_notifications', [
            'user_id' => $member->id,
            'type' => 'verification',
        ]);
    }

    public function test_rejecting_a_verification_carries_the_reason(): void
    {
        $member = $this->member('Bea Member');
        $admin = $this->admin();

        $this->actingAs($admin)
            ->postJson("/api/admin/users/{$member->id}/reject", ['reason' => 'Blurry document'])
            ->assertOk();

        $notification = MemberNotification::where('user_id', $member->id)
            ->where('type', 'verification')
            ->latest()
            ->first();

        $this->assertNotNull($notification);
        $this->assertStringContainsString('Blurry document', $notification->body);
    }

    // ------------------------------------------------------------------
    // Listing moderation (owner previously had no way to know why it vanished)
    // ------------------------------------------------------------------

    public function test_removing_a_listing_notifies_its_owner(): void
    {
        $owner = $this->member('Cara Owner');
        $listing = $this->listingFor($owner);
        $admin = $this->admin();

        $this->actingAs($admin)
            ->postJson("/api/admin/resources/{$listing->id}/moderate", [
                'action' => 'remove',
                'reason' => 'Prohibited item',
            ])
            ->assertOk();

        $this->assertDatabaseHas('member_notifications', [
            'user_id' => $owner->id,
            'type' => 'listing',
        ]);
    }

    public function test_restoring_a_listing_tells_the_owner_it_is_live_again(): void
    {
        $owner = $this->member('Dan Owner');
        $listing = $this->listingFor($owner);
        $listing->update(['status' => 'hidden', 'is_active' => false]);
        $admin = $this->admin();

        $this->actingAs($admin)
            ->postJson("/api/admin/resources/{$listing->id}/moderate", ['action' => 'restore'])
            ->assertOk();

        $notification = MemberNotification::where('user_id', $owner->id)
            ->where('type', 'listing')
            ->latest()
            ->first();

        $this->assertNotNull($notification);
        $this->assertStringContainsString('live again', $notification->title.$notification->body);
    }

    // ------------------------------------------------------------------
    // Preference endpoints
    // ------------------------------------------------------------------

    public function test_preferences_default_to_everything_on(): void
    {
        $member = $this->member('Elle Member');

        $this->actingAs($member)
            ->getJson('/api/notification-preferences')
            ->assertOk()
            ->assertJsonPath('notification_preferences.enabled', true)
            ->assertJsonPath('notification_preferences.messages', true)
            ->assertJsonPath('notification_preferences.exchanges', true)
            ->assertJsonPath('notification_preferences.announcements', true)
            ->assertJsonPath('notification_preferences.account', true);
    }

    public function test_a_partial_update_keeps_the_other_preferences(): void
    {
        $member = $this->member('Faye Member');

        $this->actingAs($member)
            ->putJson('/api/notification-preferences', ['exchanges' => false])
            ->assertOk()
            ->assertJsonPath('notification_preferences.exchanges', false)
            ->assertJsonPath('notification_preferences.messages', true);

        // A second, unrelated toggle must not reset the first.
        $this->actingAs($member)
            ->putJson('/api/notification-preferences', ['messages' => false])
            ->assertOk()
            ->assertJsonPath('notification_preferences.messages', false)
            ->assertJsonPath('notification_preferences.exchanges', false);
    }

    public function test_preferences_are_rejected_for_guests(): void
    {
        $this->putJson('/api/notification-preferences', ['messages' => false])
            ->assertUnauthorized();
    }
}
