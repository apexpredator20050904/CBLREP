<?php

namespace App\Services;

use App\Models\DeviceToken;
use Illuminate\Support\Facades\Log;
use Kreait\Firebase\Contract\Messaging;
use Kreait\Firebase\Factory;
use Kreait\Firebase\Messaging\CloudMessage;
use Kreait\Firebase\Messaging\Notification;

/**
 * Sends Firebase Cloud Messaging pushes to a member's registered devices.
 *
 * Every method is best-effort and never throws: a push failure must never break
 * the request that triggered it (posting a chat message, approving an exchange,
 * …). The in-app `member_notifications` row remains the source of truth, and the
 * mobile app still polls as a fallback.
 *
 * With no service-account key configured (local dev, CI) the service quietly
 * no-ops instead of erroring.
 */
class PushService
{
    private ?Messaging $messaging = null;

    private bool $resolved = false;

    /** Whether a usable service-account credential is present. */
    public function isConfigured(): bool
    {
        return $this->messaging() !== null;
    }

    /**
     * Pushes a notification to every device the given member has registered.
     *
     * @param  array<string, mixed>  $data  extra data payload (coerced to strings)
     */
    public function sendToUser(int $userId, string $title, string $body, array $data = []): void
    {
        $tokens = DeviceToken::where('user_id', $userId)->pluck('token')->all();

        if ($tokens === []) {
            return;
        }

        $this->sendToTokens($tokens, $title, $body, $data);
    }

    /**
     * Sends the same notification to a set of tokens, pruning any FCM reports
     * as permanently invalid so future sends do not keep paying for dead ones.
     *
     * @param  list<string>  $tokens
     * @param  array<string, mixed>  $data
     */
    public function sendToTokens(array $tokens, string $title, string $body, array $data = []): void
    {
        $tokens = array_values(array_filter(
            $tokens,
            static fn ($token) => is_string($token) && $token !== '',
        ));

        if ($tokens === []) {
            return;
        }

        $messaging = $this->messaging();
        if ($messaging === null) {
            return;
        }

        // FCM data payloads must be string → string.
        $payload = [];
        foreach ($data as $key => $value) {
            if ($value === null) {
                continue;
            }
            $payload[(string) $key] = is_scalar($value)
                ? (string) $value
                : (string) json_encode($value);
        }

        $message = CloudMessage::new()
            ->withNotification(Notification::create($title, $body))
            ->withData($payload);

        try {
            $report = $messaging->sendMulticast($message, $tokens);
        } catch (\Throwable $e) {
            Log::warning('[CBLREP] FCM send failed: '.$e->getMessage());

            return;
        }

        $stale = array_unique(array_merge(
            $report->invalidTokens(),
            $report->unknownTokens(),
        ));

        if ($stale !== []) {
            DeviceToken::whereIn('token', $stale)->delete();
        }
    }

    /**
     * Lazily builds the Messaging client from the service-account JSON.
     *
     * Returns null (logging once) when no credential is configured, so a local
     * install without a Firebase key still works — it just cannot push.
     */
    private function messaging(): ?Messaging
    {
        if ($this->resolved) {
            return $this->messaging;
        }
        $this->resolved = true;

        $credentials = config('services.firebase.credentials');

        if (! is_string($credentials) || $credentials === '' || ! is_file($credentials)) {
            Log::info('[CBLREP] FCM not configured — set FIREBASE_CREDENTIALS to the service-account JSON path.');

            return null;
        }

        try {
            $factory = (new Factory)->withServiceAccount($credentials);

            $projectId = config('services.firebase.project_id');
            if (is_string($projectId) && $projectId !== '') {
                $factory = $factory->withProjectId($projectId);
            }

            $this->messaging = $factory->createMessaging();
        } catch (\Throwable $e) {
            Log::error('[CBLREP] FCM client init failed: '.$e->getMessage());
            $this->messaging = null;
        }

        return $this->messaging;
    }
}
