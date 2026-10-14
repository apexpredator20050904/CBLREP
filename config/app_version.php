<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Mobile app release channel
    |--------------------------------------------------------------------------
    | The Flutter client checks GET /api/app-version on launch to discover
    | whether a newer APK exists. Everything the app needs to decide is served
    | from these values, which are set per release rather than hardcoded in
    | the app — a shipped binary can always be told about a newer one.
    |
    | The APK itself is hosted as a GitHub Release asset (the only channel the
    | project distributes through), so `apk_url` is an absolute https URL.
    |
    |   APP_VERSION_CODE            integer versionCode of the newest release;
    |                              compared against the installed build number.
    |   APP_VERSION_NAME            human-readable version (e.g. 1.2.0).
    |   APP_MIN_SUPPORTED_CODE      builds below this are told to update and
    |                              cannot dismiss the prompt. Keep at 1 until an
    |                              API contract change genuinely breaks old apps.
    |   APP_APK_URL                 absolute download URL. Leave EMPTY to switch
    |                              the update prompt off entirely (used by the
    |                              dev/ngrok backend so testers are not nagged).
    |   APP_APK_SHA256              optional integrity hash of the APK.
    |   APP_RELEASE_NOTES           short text shown in the update dialog.
    */

    'version_code' => (int) env('APP_VERSION_CODE', 1),

    'version_name' => (string) env('APP_VERSION_NAME', '1.0.0'),

    'min_supported_code' => (int) env('APP_MIN_SUPPORTED_CODE', 1),

    'apk_url' => (string) env('APP_APK_URL', ''),

    'sha256' => (string) env('APP_APK_SHA256', ''),

    'notes' => (string) env('APP_RELEASE_NOTES', ''),

];
