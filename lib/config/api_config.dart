/// Compile-time API configuration for the CBLREP mobile client.
///
/// Resolution order (see `ApiService.baseUrlCandidates` in
/// `lib/core/api_service.dart`):
///
///   1. `--dart-define=CBLREP_API_URL=https://…`  — wins, per build
///   2. [kCblrepApiUrlFallback]                    — used when the define is absent
///
/// The defense build is produced with the explicit `--dart-define` so the URL
/// is visible in the build command, but this fallback keeps a plain
/// `flutter build apk --release` (or a CI run that forgets the flag) pointed at
/// the live tunnel instead of a dead sentinel host.
///
/// Keep this the ONLY place a production URL is written. Never hardcode a host
/// anywhere else.
///
/// To re-point the app at a new tunnel, edit the single line below.
const String kCblrepApiUrlFallback =
    'https://contest-bunny-unsorted.ngrok-free.dev';

/// Sentinel for "no real URL configured yet". `ApiService` treats this exact
/// value as *unset* so a release build says so loudly (see
/// `ApiService.releaseConfigError`) instead of trying to reach a fake host.
const String kCblrepApiUrlPlaceholder =
    'https://REPLACE-WITH-NGROK-SUBDOMAIN.ngrok-free.app';
