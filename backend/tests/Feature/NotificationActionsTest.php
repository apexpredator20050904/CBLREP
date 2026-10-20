<?php

namespace Tests\Feature;

use App\Models\DeviceToken;
use App\Models\MemberNotification;
use App\Models\User;
use App\Services\AppUpdateNotifier;
use App\Services\PushService;
use Tests\TestCase;

/**
 * The member's own control over their inbox.
 *
 *   - marking the whole inbox as read,
 *   - deleting one notification,
 *   - clearing the inbox entirely,
 *   - and the announcement that a new app build is available.
 *
 * All of it is scoped to the caller: one account can never read, alter or
 * remove another account's history.
 */
class NotificationActionsTest extends TestCase
{
    /**
     * A PushService stand-in that records what would have been pushed.
     *
     * The real service talks to Firebase, and Firebase answers a made-up
     * token with "unregistered" - which makes PushService prune the row. A
     * test that used the live service would therefore lose the device it
     * just created, so the announcement tests never reach the network.
     */
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

    protected function setUp(): void
    {
        parent::setUp();

        // Every push in this file is recorded, never sent.
        $this->app->instance(PushService::class, $this->spyPush());
    }

    /** The tokens the notifier would have pushed to. */
    private function pushedTokens(): array
    {
        $spy = $this->app->make(PushService::class);

        return collect($spy->batches)->flatMap(fn (array $batch) => $batch['tokens'])->all();
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private function member(string $name = 'Test Member'): User
    {
        return User::create([
            // The users table carries a unique index on the name and this
            // suite shares the live development database, so the fixture name
            // carries a unique token.
            'name' => $name.' '.uniqid(),
            'email' => strtolower(preg_replace('/[^a-z]+/i', '-', $name)).'-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }

    private function notificationFor(User $user, array $attributes = []): MemberNotification
    {
        return MemberNotification::create(array_merge([
            'user_id' => $user->id,
            'type' => 'system',
            'title' => 'Something happened',
            'body' => 'The details of the thing that happened.',
        ], $attributes));
    }

    // ------------------------------------------------------------------
    // Mark all as read
    // ------------------------------------------------------------------

    public function test_marking_everything_read_stamps_the_unread_rows(): void
    {
        $member = $this->member('Inbox Owner');
        $this->notificationFor($member);
        $this->notificationFor($member);
        $this->notificationFor($member);

        $this->actingAs($member)
            ->putJson('/api/notifications/read-all')
            ->assertOk()
            ->assertJsonPath('unread_count', 0)
            ->assertJsonPath('updated', 3);

        $this->assertSame(
            0,
            MemberNotification::where('user_id', $member->id)->whereNull('read_at')->count(),
            'No notification may be left unread.'
        );
    }

    public function test_marking_everything_read_leaves_the_original_read_time_alone(): void
    {
        $member = $this->member('Inbox Keeper');
        $readEarlier = now()->subDays(3)->startOfSecond();
        $alreadyRead = $this->notificationFor($member, ['read_at' => $readEarlier]);

        $this->actingAs($member)->putJson('/api/notifications/read-all')->assertOk();

        $alreadyRead->refresh();
        $this->assertTrue(
            $alreadyRead->read_at->equalTo($readEarlier),
            'A notification that was already read must keep the moment it was read.'
        );
    }

    public function test_marking_everything_read_does_not_touch_another_members_inbox(): void
    {
        $member = $this->member('Inbox Holder');
        $other = $this->member('Other Holder');
        $theirs = $this->notificationFor($other);

        $this->actingAs($member)->putJson('/api/notifications/read-all')->assertOk();

        $this->assertNull($theirs->fresh()->read_at, 'Another member\'s notification must stay unread.');
    }

    public function test_a_guest_cannot_mark_notifications_read(): void
    {
        $this->putJson('/api/notifications/read-all')->assertUnauthorized();
    }

    // ------------------------------------------------------------------
    // Delete one
    // ------------------------------------------------------------------

    public function test_a_member_can_delete_a_notification(): void
    {
        $member = $this->member('Deleter');
        $notification = $this->notificationFor($member);

        $this->actingAs($member)
            ->deleteJson("/api/notifications/{$notification->id}")
            ->assertOk()
            ->assertJsonPath('deleted', true)
            ->assertJsonPath('notification_id', $notification->id);

        $this->assertNull(
            MemberNotification::find($notification->id),
            'The notification must be gone from the database.'
        );
    }

    public function test_deleting_a_notification_removes_it_from_the_listing(): void
    {
        $member = $this->member('Deleter Two');
        $this->notificationFor($member);
        $doomed = $this->notificationFor($member);

        $this->actingAs($member)->deleteJson("/api/notifications/{$doomed->id}")->assertOk();

        $ids = collect($this->actingAs($member)->getJson('/api/notifications')->json('notifications'))
            ->pluck('id')
            ->all();

        $this->assertNotContains($doomed->id, $ids, 'The deleted notification must not be listed.');
    }

    public function test_deleting_someone_elses_notification_is_refused(): void
    {
        $member = $this->member('Sneaky');
        $other = $this->member('Victim');
        $theirs = $this->notificationFor($other);

        $this->actingAs($member)
            ->deleteJson("/api/notifications/{$theirs->id}")
            ->assertNotFound();

        $this->assertNotNull(MemberNotification::find($theirs->id), 'The notification must survive.');
    }

    public function test_a_guest_cannot_delete_notifications(): void
    {
        $this->deleteJson('/api/notifications/1')->assertUnauthorized();
    }

    public function test_the_unread_count_follows_a_deletion(): void
    {
        $member = $this->member('Counter');
        $unread = $this->notificationFor($member);
        $this->notificationFor($member, ['read_at' => now()]);

        $this->actingAs($member)
            ->deleteJson("/api/notifications/{$unread->id}")
            ->assertOk()
            ->assertJsonPath('unread_count', 0);
    }

    // ------------------------------------------------------------------
    // Clear the whole inbox
    // ------------------------------------------------------------------

    public function test_a_member_can_clear_their_whole_inbox(): void
    {
        $member = $this->member('Cleaner');
        $other = $this->member('Untouched');
        $theirs = $this->notificationFor($other);
        $this->notificationFor($member);
        $this->notificationFor($member);

        $this->actingAs($member)
            ->deleteJson('/api/notifications')
            ->assertOk()
            ->assertJsonPath('deleted', 2)
            ->assertJsonPath('unread_count', 0);

        $this->assertSame(
            0,
            MemberNotification::where('user_id', $member->id)->count(),
            'The member\'s inbox must be empty.'
        );
        $this->assertNotNull(
            MemberNotification::find($theirs->id),
            'Another member\'s inbox must be untouched.'
        );
    }

    // ------------------------------------------------------------------
    // "A new version is available"
    // ------------------------------------------------------------------

    private function configureRelease(int $versionCode = 99, string $versionName = '9.9.9'): void
    {
        config()->set('app_version.version_code', $versionCode);
        config()->set('app_version.version_name', $versionName);
        config()->set('app_version.apk_url', 'https://example.test/app-release.apk');
        config()->set('app_version.notes', 'A brand new build with fixes.');
    }

    private function deviceFor(User $user, ?int $buildNumber, string $token = 'tok'): DeviceToken
    {
        return DeviceToken::create([
            'user_id' => $user->id,
            'token' => $token.'-'.uniqid(),
            'platform' => 'android',
            'build_number' => $buildNumber,
        ]);
    }

    public function test_the_announcement_reaches_only_members_on_an_older_build(): void
    {
        $this->configureRelease(50);

        $behind = $this->member('Behind');
        $current = $this->member('Current');
        $unknown = $this->member('Unknown');

        $this->deviceFor($behind, 49);
        $this->deviceFor($current, 50);
        $this->deviceFor($unknown, null);

        // The suite shares the live development database, which has devices of
        // its own, so the audience is asserted member by member rather than as
        // a global count.
        app(AppUpdateNotifier::class)->broadcast();

        $this->assertSame(
            1,
            MemberNotification::where('user_id', $behind->id)->where('type', 'app_update')->count(),
            'A member on an older build must be told.'
        );
        $this->assertSame(
            1,
            MemberNotification::where('user_id', $unknown->id)->where('type', 'app_update')->count(),
            'A member whose build is unknown must be told - we cannot prove they are current.'
        );
        $this->assertSame(
            0,
            MemberNotification::where('user_id', $current->id)->where('type', 'app_update')->count(),
            'A member already on this build must not be bothered.'
        );
    }

    public function test_the_announcement_is_recorded_with_the_release_it_is_about(): void
    {
        $this->configureRelease(77, '1.7.7');
        $member = $this->member('Listener');
        $this->deviceFor($member, 10);

        app(AppUpdateNotifier::class)->broadcast();

        $row = MemberNotification::where('user_id', $member->id)->where('type', 'app_update')->latest()->first();

        $this->assertNotNull($row);
        $this->assertSame(77, $row->app_version_code);
        $this->assertSame(77, $row->data['version_code']);
        $this->assertSame('1.7.7', $row->data['version_name']);
        $this->assertSame('update', $row->data['action']);
        $this->assertStringContainsString('1.7.7', $row->title);
    }

    public function test_the_announcement_is_not_sent_twice_for_the_same_release(): void
    {
        $this->configureRelease(88);
        $member = $this->member('Once Only');
        $this->deviceFor($member, 5);

        $notifier = app(AppUpdateNotifier::class);

        $notifier->broadcast();
        $second = $notifier->broadcast();

        $this->assertSame(0, $second['notified'], 'A replay must not notify anybody again.');
        $this->assertSame(
            1,
            MemberNotification::where('user_id', $member->id)->where('type', 'app_update')->count(),
            'The member must still hold exactly one notice for this release.'
        );
    }

    public function test_forcing_the_announcement_sends_it_again(): void
    {
        $this->configureRelease(88);
        $member = $this->member('Twice');
        $this->deviceFor($member, 5);

        $notifier = app(AppUpdateNotifier::class);

        $notifier->broadcast();
        $firstId = MemberNotification::where('user_id', $member->id)->where('type', 'app_update')->value('id');

        $notifier->broadcast(force: true);
        $secondId = MemberNotification::where('user_id', $member->id)->where('type', 'app_update')->value('id');

        $this->assertNotNull($secondId);
        $this->assertNotSame($firstId, $secondId, 'A forced re-send must write a fresh notice.');
    }

    public function test_a_member_who_muted_updates_is_not_pushed_to(): void
    {
        $this->configureRelease(88);
        $member = $this->member('Muted');
        $member->forceFill(['notification_preferences' => ['updates' => false]])->save();
        $device = $this->deviceFor($member, 5);

        app(AppUpdateNotifier::class)->broadcast();

        // The inbox row is still written - the record is the source of truth -
        // but the push must not leave the device.
        $this->assertSame(
            1,
            MemberNotification::where('user_id', $member->id)->where('type', 'app_update')->count(),
            'The member still gets the notice in their inbox.'
        );

        $this->assertNotContains(
            $device->token,
            $this->pushedTokens(),
            'A member who muted app updates must not be pushed to.'
        );
    }

    public function test_the_announcement_refuses_when_no_release_channel_is_configured(): void
    {
        config()->set('app_version.apk_url', '');

        $this->expectException(\RuntimeException::class);

        app(AppUpdateNotifier::class)->broadcast();
    }

    public function test_the_device_token_records_the_build_the_app_is_running(): void
    {
        $member = $this->member('Reporter');
        $token = 'tok-'.uniqid();

        $this->actingAs($member)
            ->postJson('/api/device-tokens', [
                'token' => $token,
                'platform' => 'android',
                'build_number' => 42,
            ])
            ->assertCreated();

        $this->assertSame(42, DeviceToken::where('token', $token)->value('build_number'));
    }
}
