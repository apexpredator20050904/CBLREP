<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;

/**
 * Serves the mobile release channel to the Flutter client.
 *
 * The app polls this on launch (and from Settings → Check for updates) to
 * learn whether a newer APK is available beyond GitHub Releases, which has no
 * unauthenticated "latest version" contract the app can rely on.
 *
 * Public by design: an outdated build must be able to discover its replacement
 * before the member has signed in, and the payload is non-sensitive config
 * (version numbers + a public download URL).
 */
class AppVersionController extends Controller
{
    public function show()
    {
        $apkUrl = (string) config('app_version.apk_url');

        return response()->json([
            'version_code' => (int) config('app_version.version_code'),
            'version_name' => (string) config('app_version.version_name'),
            'min_supported_code' => (int) config('app_version.min_supported_code'),
            // Empty URL = "no update channel configured". The client treats it
            // as a no-op so a dev/ngrok backend can stay silent.
            'apk_url' => $apkUrl,
            'sha256' => (string) config('app_version.sha256'),
            'notes' => (string) config('app_version.notes'),
        ]);
    }
}
