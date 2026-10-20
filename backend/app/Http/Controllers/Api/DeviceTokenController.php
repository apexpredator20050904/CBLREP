<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\Request;

/**
 * FCM device-token registration for the mobile app.
 *
 * The app POSTs its token after sign-in (and on token rotation) and DELETEs it
 * on sign-out, so a signed-out device stops receiving the member's alerts.
 */
class DeviceTokenController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'token' => ['required', 'string', 'max:512'],
            'platform' => ['nullable', 'string', 'in:android,ios,web'],
            // The build the device is running. The app sends it on every
            // registration, so the server always knows who is behind and can
            // notify only those members when a new release is published.
            'build_number' => ['nullable', 'integer', 'min:0', 'max:100000'],
        ]);

        // updateOrCreate keyed on the token: if the device previously belonged
        // to another member, the row is reassigned so pushes never reach the
        // wrong person after a shared-device handover.
        $deviceToken = DeviceToken::updateOrCreate(
            ['token' => $validated['token']],
            [
                'user_id' => $request->user()->id,
                'platform' => $validated['platform'] ?? 'android',
                'build_number' => $validated['build_number'] ?? null,
                'last_used_at' => now(),
            ],
        );

        return response()->json(['device_token' => $deviceToken], 201);
    }

    public function destroy(Request $request)
    {
        $validated = $request->validate([
            'token' => ['required', 'string', 'max:512'],
        ]);

        // Scoped to the caller: a member can only unregister their own token,
        // so one account cannot silence another account's notifications.
        DeviceToken::where('user_id', $request->user()->id)
            ->where('token', $validated['token'])
            ->delete();

        return response()->json(['deleted' => true]);
    }
}
