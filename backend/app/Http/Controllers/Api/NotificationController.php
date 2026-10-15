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
            'unread_count' => MemberNotification::where('user_id', $request->user()->id)->whereNull('read_at')->count(),
            'meta' => ['current_page' => $items->currentPage(), 'last_page' => $items->lastPage()],
        ]);
    }

    public function read(Request $request, int $id)
    {
        $notification = MemberNotification::where('user_id', $request->user()->id)->findOrFail($id);
        $notification->update(['read_at' => now()]);
        return response()->json(['notification' => $notification->fresh()]);
    }
}
