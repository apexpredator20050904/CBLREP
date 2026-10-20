<?php

namespace App\Services;

use App\Models\DeviceToken;
use App\Models\MemberNotification;
use App\Models\User;

/**
 * The single place that turns a domain event into a member alert.
 *
 * Before this service every controller wrote its own `member_notifications`
 * row and — with one exception — forgot to push, so a member only learned about
 * a barter proposal, a verification decision or a moderation action if the app
 * happened to be open. Routing every event through `notify()` guarantees the
 * two halves stay together: the inbox row is always written (it is the source
 * of truth the app and the admin console read), and the FCM push is sent only
 * when the member's own preferences allow it.
 *
 * The push is always best-effort: PushService never throws, and a failure here
 * must never roll back the action that triggered it.
 */
class NotificationService
{
    public const CATEGORY_MESSAGES = 'messages';
    public const CATEGORY_EXCHANGES = 'exchanges';
    public const CATEGORY_ANNOUNCEMENTS = 'announcements';
    public const CATEGORY_ACCOUNT = 'account';

    /**
     * "A new version of the app is available".
     *
     * Its own category so a member can silence release pings at the OS level
     * without also muting barangay announcements, and the other way round.
     */
    public const CATEGORY_UPDATES = 'updates';

    /**
     * Android notification channel per category.
     *
     * These ids must stay in step with the channels the app creates in
     * mobile/lib/core/push_service.dart. A per-category channel lets a member
     * mute barter alerts at the OS level without silencing messages.
     */
    private const CHANNELS = [
        self::CATEGORY_MESSAGES => 'cblrep_messages',
        self::CATEGORY_EXCHANGES => 'cblrep_exchanges',
        self::CATEGORY_ANNOUNCEMENTS => 'cblrep_announcements',
        self::CATEGORY_ACCOUNT => 'cblrep_account',
        self::CATEGORY_UPDATES => 'cblrep_updates',
    ];

    public function __construct(private PushService $push) {}

    /**
     * Record an in-app notification and, if the member allows it, push it.
     *
     * @param  array<string, mixed>  $data  structured payload for deep links
     * @return MemberNotification|null null when a matching row already existed
     */
    public function notify(
        int $userId,
        string $category,
        string $type,
        string $title,
        string $body,
        array $data = [],
        array $uniqueBy = [],
    ): ?MemberNotification {
        $notification = $this->record($userId, $type, $title, $body, $data, $uniqueBy);

        // A duplicate (e.g. re-sending an announcement) must not re-push.
        if ($notification === null) {
            return null;
        }

        $this->push($userId, $category, $type, $title, $body, $data);

        return $notification;
    }

    /**
     * Record the same notification for many members and push it in batches.
     *
     * Built for announcement fan-out: sending one FCM request per member would
     * mean hundreds of sequential round-trips inside a single admin request, so
     * the tokens are collected once and sent 500 at a time (FCM's multicast
     * ceiling). Each member's own preferences still decide whether their
     * devices are included.
     *
     * @param  list<int>  $userIds
     * @param  array<string, mixed>  $data
     * @param  array<string, mixed>  $uniqueBy
     * @return int the number of members for whom a row was newly recorded
     */
    public function notifyMany(
        array $userIds,
        string $category,
        string $type,
        string $title,
        string $body,
        array $data = [],
        array $uniqueBy = [],
    ): int {
        $created = [];

        foreach ($userIds as $userId) {
            if ($this->record((int) $userId, $type, $title, $body, $data, $uniqueBy) !== null) {
                $created[] = (int) $userId;
            }
        }

        if ($created === []) {
            return 0;
        }

        // A replay must not re-push, so only members who got a fresh row are
        // candidates — and only those whose preferences allow this category.
        $allowed = User::whereIn('id', $created)->get()
            ->filter(static fn (User $user) => $user->wantsPush($category))
            ->pluck('id')
            ->all();

        $this->pushMany($allowed, $category, $type, $title, $body, $data);

        return count($created);
    }

    /** Send one notification to many members, batching their device tokens. */
    private function pushMany(
        array $userIds,
        string $category,
        string $type,
        string $title,
        string $body,
        array $data,
    ): void {
        if ($userIds === []) {
            return;
        }

        $channel = self::CHANNELS[$category] ?? null;
        $payload = array_merge($data, [
            'type' => $type,
            'category' => $category,
            'channel' => $channel,
        ]);

        $tokens = DeviceToken::whereIn('user_id', $userIds)->pluck('token')->all();

        foreach (array_chunk($tokens, 500) as $chunk) {
            $this->push->sendToTokens($chunk, $title, $body, $payload, $channel);
        }
    }

    /**
     * Write the inbox row, honouring an optional uniqueness key so a broadcast
     * can be replayed without duplicating (or re-pushing) it.
     *
     * @param  array<string, mixed>  $data
     * @param  array<string, mixed>  $uniqueBy
     */
    private function record(
        int $userId,
        string $type,
        string $title,
        string $body,
        array $data,
        array $uniqueBy,
    ): ?MemberNotification {
        $attributes = array_merge(['user_id' => $userId], $uniqueBy);

        if ($uniqueBy !== [] && MemberNotification::where($attributes)->exists()) {
            return null;
        }

        return MemberNotification::create($attributes + [
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data,
        ]);
    }

    /** Send the push if the member has device tokens and allows this category. */
    private function push(
        int $userId,
        string $category,
        string $type,
        string $title,
        string $body,
        array $data,
    ): void {
        $user = User::find($userId);

        if (! $user || ! $user->wantsPush($category)) {
            return;
        }

        $channel = self::CHANNELS[$category] ?? null;

        $this->push->sendToUser($userId, $title, $body, array_merge($data, [
            'type' => $type,
            'category' => $category,
            'channel' => $channel,
        ]), $channel);
    }
}
