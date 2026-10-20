<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

/**
 * GET/PUT a member's push-notification preferences.
 *
 * These are the server-side mirror of the mobile Settings toggles. They live on
 * the server because only the server sends FCM pushes — a device-local toggle
 * could never stop a push the backend had already decided to send.
 */
class NotificationPreferenceController extends Controller
{
    public function show(Request $request)
    {
        $user = $request->user();

        return response()->json([
            'notification_preferences' => $user->notificationPreferences(),
            // False until the member (via the app) has ever saved a choice, so
            // the client knows to seed the server from its local settings.
            'configured' => $user->notification_preferences !== null,
        ]);
    }

    public function update(Request $request)
    {
        $validated = $request->validate([
            'enabled' => ['sometimes', 'boolean'],
            'messages' => ['sometimes', 'boolean'],
            'exchanges' => ['sometimes', 'boolean'],
            'announcements' => ['sometimes', 'boolean'],
            'account' => ['sometimes', 'boolean'],
            'updates' => ['sometimes', 'boolean'],
        ]);

        $user = $request->user();

        // Merge onto the effective set so a partial update (one toggle) never
        // resets the others.
        $preferences = array_merge($user->notificationPreferences(), $validated);
        $user->forceFill(['notification_preferences' => $preferences])->save();

        return response()->json([
            'notification_preferences' => $user->fresh()->notificationPreferences(),
        ]);
    }
}
