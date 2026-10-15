/// Compile-time API configuration for the CBLREP mobile client.
///
/// Resolution order (see `ApiService.baseUrlCandidates` in
/// `lib/core/api_service.dart`):
///
///   1. `--dart-define=CBLREP_API_URL=https://…`  — wins, per build
///   2. [kCblrepApiUrlFallback]                    — used when the define is absent
///
/// The production origin is always supplied at build time, e.g.
///
///   ./build_release.sh https://api.your-domain.com
///
/// so no live URL is hardcoded here. When the define is absent the fallback
/// below resolves to the [kCblrepApiUrlPlaceholder] sentinel, which `ApiService`
/// treats as "unconfigured": a release build then reports the problem loudly
/// (see `ApiService.releaseConfigError`) instead of silently pointing at a
/// stale host.
const String kCblrepApiUrlFallback = kCblrepApiUrlPlaceholder;

/// Sentinel for "no real URL configured yet". `ApiService` treats this exact
/// value as *unset* so a release build fails loudly rather than trying to reach
/// a fake host.
///
/// Set [kCblrepApiUrlFallback] to a real origin only if you deliberately want a
/// plain `flutter build apk --release` (no `--dart-define`) to ship a live URL.
const String kCblrepApiUrlPlaceholder =
    'https://REPLACE-WITH-YOUR-API-HOST.example';
