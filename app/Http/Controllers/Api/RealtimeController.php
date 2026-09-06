<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;

/**
 * Real-time messaging + presence endpoints used by the React frontend.
 *
 * The UI strokes each chat message as a flat object addressed by the
 * neighbour's email (fromId/toId). We persist that exact shape to a small
 * JSON store (storage/app/realtime.json) so conversation history survives
 * server restarts and round-trips unchanged to the client.
 */
class RealtimeController extends Controller
{
    private function storePath(): string
    {
        return storage_path('app/realtime.json');
    }

    private function readStore(): array
    {
        $default = ['messages' => [], 'presence' => []];

        if (! File::exists($this->storePath())) {
            return $default;
        }

        $data = json_decode(File::get($this->storePath()), true);
        if (! is_array($data)) {
            return $default;
        }

        return [
            'messages' => isset($data['messages']) && is_array($data['messages'])
                ? array_values($data['messages'])
                : [],
            'presence' => isset($data['presence']) && is_array($data['presence'])
                ? $data['presence']
                : [],
        ];
    }

    private function writeStore(array $data): void
    {
        File::ensureDirectoryExists(dirname($this->storePath()));
        File::put(
            $this->storePath(),
            json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT),
        );
    }

    private function normalize(array $message): array
    {
        $message['id'] = $message['id']
            ?? ('sg-'.(microtime(true) * 1000).'-'.random_int(1000, 9999));
        $message['createdAt'] = $message['createdAt'] ?? (int) round(microtime(true) * 1000);

        return $message;
    }

    /**
     * GET /api/messages?email=... — return the conversation history for a user.
     */
    public function index(Request $request)
    {
        $email = strtolower(trim((string) $request->query('email', '')));

        $messages = collect($this->readStore()['messages'])
            ->filter(function ($m) use ($email) {
                if (! is_array($m)) {
                    return false;
                }
                $to = strtolower((string) ($m['toId'] ?? $m['toEmail'] ?? ''));
                $from = strtolower((string) ($m['fromId'] ?? $m['fromEmail'] ?? ''));
                if ($email === '') {
                    return true;
                }

                return $to === $email || $from === $email;
            })
            ->values()
            ->all();

        return response()->json(['messages' => $messages]);
    }

    /**
     * POST /api/messages — store a chat message.
     */
    public function store(Request $request)
    {
        $message = array_filter((array) $request->all(), fn ($v) => $v !== null);
        $to = strtolower((string) ($message['toId'] ?? $message['toEmail'] ?? ''));

        if ($to === '') {
            return response()->json(['message' => 'A recipient is required.'], 400);
        }

        $message = $this->normalize($message);

        $data = $this->readStore();
        $data['messages'][] = $message;
        $this->writeStore($data);

        return response()->json(['ok' => true, 'message' => $message], 201);
    }

    /**
     * GET /api/stream — Server-Sent Events endpoint.
     *
     * php artisan serve runs a single PHP worker, so keeping a blocking
     * connection open here would freeze every other request. We therefore
     * complete immediately; the React client then stays in browser-local
     * delivery mode (BroadcastChannel + persisted history) until it
     * re-connects.
     */
    public function stream(Request $request)
    {
        return response()->json([
            'ok' => true,
            'message' => 'SSE stream configured; use /api/messages for history.',
        ]);
    }

    /**
     * GET /api/presence — returns the currently-online members.
     */
    public function presenceIndex(Request $request)
    {
        $now = (int) (microtime(true) * 1000);
        $online = [];

        foreach ($this->readStore()['presence'] as $email => $record) {
            $updatedAt = (int) ($record['updatedAt'] ?? 0);
            if ($updatedAt > 0 && ($now - $updatedAt) < 50000) {
                $online[] = array_merge((array) $record, ['email' => $email]);
            }
        }

        return response()->json(['members' => array_values($online)]);
    }

    /**
     * POST /api/presence — announce that the current user is online.
     */
    public function presenceStore(Request $request)
    {
        $record = array_filter((array) $request->all(), fn ($v) => $v !== null);
        $email = strtolower((string) ($record['email'] ?? $record['id'] ?? ''));

        if ($email !== '') {
            $data = $this->readStore();
            $record['updatedAt'] = (int) (microtime(true) * 1000);
            $data['presence'][$email] = $record;
            $this->writeStore($data);
        }

        return response()->json(['ok' => true]);
    }
}