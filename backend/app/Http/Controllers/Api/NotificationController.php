<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MemberNotification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request)
    {
        $items = MemberNotification::where('user_id', $request->user()->id)
            ->latest()
            ->paginate(min((int) $request->query('per_page', 25), 100));

        return response()->json([
            'notifications' => $items->getCollection(),
            'unread_count' => $this->unreadCount($request),
            'meta' => ['current_page' => $items->currentPage(), 'last_page' => $items->lastPage()],
        ]);
    }

    public function read(Request $request, int $id)
    {
        $notification = MemberNotification::where('user_id', $request->user()->id)->findOrFail($id);
        $notification->update(['read_at' => now()]);
        return response()->json(['notification' => $notification->fresh()]);
    }

    /**
     * Mark every unread notification as read.
     *
     * Only the UNREAD rows are stamped: a notification that was already read
     * keeps the timestamp of when it was actually read, so the inbox keeps an
     * honest history rather than flattening it to "read just now".
     */
    public function readAll(Request $request)
    {
        $updated = MemberNotification::where('user_id', $request->user()->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json([
            'updated' => $updated,
            'unread_count' => 0,
        ]);
    }

    /**
     * Delete one notification.
     *
     * Scoped to the caller, so a member can only remove their own rows — one
     * account can never silence another account's history.
     */
    public function destroy(Request $request, int $id)
    {
        $notification = MemberNotification::where('user_id', $request->user()->id)->findOrFail($id);
        $notification->delete();

        return response()->json([
            'deleted' => true,
            'notification_id' => $id,
            'unread_count' => $this->unreadCount($request),
        ]);
    }

    /** Delete every notification belonging to the caller. */
    public function destroyAll(Request $request)
    {
        $deleted = MemberNotification::where('user_id', $request->user()->id)->delete();

        return response()->json([
            'deleted' => $deleted,
            'unread_count' => 0,
        ]);
    }

    /** How many of the caller's notifications are still unread. */
    private function unreadCount(Request $request): int
    {
        return MemberNotification::where('user_id', $request->user()->id)
            ->whereNull('read_at')
            ->count();
    }
}
