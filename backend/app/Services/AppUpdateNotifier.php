<?php

namespace App\Services;

use App\Models\DeviceToken;
use App\Models\MemberNotification;
use App\Models\User;
use RuntimeException;

/**
 * Tells members that a new build of the app is available.
 *
 * The in-app updater only reaches a member who opens the app. This service is
 * the other half of that story: when a release is published, the members who
 * are still on an older build get a push and an inbox row, so they hear about
 * the update before they next open the portal.
 *
 * Two rules keep the announcement honest:
 *
 *   - Only members who are actually behind are notified. A device that has
 *     never reported a build number counts as "behind" (we cannot prove it is
 *     current), but a device already on the newest build is skipped.
 *   - The announcement is recorded against the release it is about
 *     (`app_version_code`), so re-running it for the same version notifies
 *     nobody a second time.
 */
class AppUpdateNotifier
{
    public function __construct(private NotificationService $notifications) {}

    /**
     * Announce the currently configured release.
     *
     * @param  bool  $all   notify every member, not only the ones behind
     * @param  bool  $force re-send even if the members were already told
     * @return array{version_code: int, version_name: string, notified: int, audience: int, skipped_up_to_date: int}
     */
    public function broadcast(bool $all = false, bool $force = false): array
    {
        $versionCode = (int) config('app_version.version_code');
        $versionName = (string) config('app_version.version_name');
        $apkUrl = (string) config('app_version.apk_url');
        $notes = (string) config('app_version.notes');

        if ($apkUrl === '') {
            throw new RuntimeException(
                'No release channel is configured (APP_APK_URL is empty), so there is nothing to announce.'
            );
        }

        [$audience, $upToDate] = $this->audience($versionCode, $all);

        if ($force) {
            // Clear the previous announcement for this release so the dedup key
            // does not swallow the re-send.
            MemberNotification::where('type', 'app_update')
                ->where('app_version_code', $versionCode)
                ->delete();
        }

        $notified = $this->notifications->notifyMany(
            $audience,
            NotificationService::CATEGORY_UPDATES,
            'app_update',
            $this->title($versionName),
            $this->body($notes),
            [
                'action' => 'update',
                'version_code' => $versionCode,
                'version_name' => $versionName,
                'apk_url' => $apkUrl,
            ],
            ['app_version_code' => $versionCode],
        );

        return [
            'version_code' => $versionCode,
            'version_name' => $versionName,
            'notified' => $notified,
            'audience' => count($audience),
            'skipped_up_to_date' => $upToDate,
        ];
    }

    /**
     * Who should hear about this release.
     *
     * @return array{0: list<int>, 1: int} the member ids and how many devices
     *                                     were already on the newest build
     */
    private function audience(int $versionCode, bool $all): array
    {
        $devices = DeviceToken::query()
            ->when(! $all, fn ($query) => $query->where(
                fn ($q) => $q->whereNull('build_number')->orWhere('build_number', '<', $versionCode)
            ))
            ->get();

        $upToDate = $all
            ? 0
            : $devices->filter(fn (DeviceToken $device) => $device->build_number !== null
                && (int) $device->build_number >= $versionCode)->count();

        $ids = $devices->pluck('user_id')
            ->map(fn ($id) => (int) $id)
            ->unique()
            // The Super Administrator runs the portal; it is not a member of
            // the community and has no use for an app update notice.
            ->reject(fn (int $id) => User::find($id)?->role === User::ROLE_SUPER_ADMIN)
            ->values()
            ->all();

        return [$ids, $upToDate];
    }

    private function title(string $versionName): string
    {
        return "CBLREP v{$versionName} is available";
    }

    /** The release notes, trimmed to something a push notification can carry. */
    private function body(string $notes): string
    {
        $notes = trim(preg_replace('/\s+/', ' ', $notes) ?? '');

        if (mb_strlen($notes) > 160) {
            $notes = rtrim(mb_substr($notes, 0, 157)).'...';
        }

        return $notes === ''
            ? 'A new version of the app is ready. Tap to update.'
            : $notes.' Tap to update.';
    }
}
