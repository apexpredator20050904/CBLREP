# Building the CBLREP release APK

## The API URL is compiled in

The Flutter client has **no hardcoded backend host**. The production origin is
passed at build time and baked into the binary:

```bash
./build_release.sh https://cblrep-api.onrender.com
```

which runs:

```bash
flutter build apk --release --dart-define=CBLREP_API_URL=https://cblrep-api.onrender.com
```

`ApiService.baseUrlCandidates` (`lib/core/api_service.dart`) resolves the host at
compile time:

- **Release** builds accept `CBLREP_API_URL`, falling back to the single
  editable line `kCblrepApiUrlFallback` in `lib/config/api_config.dart` when the
  define is omitted. The emulator/LAN/loopback candidates (`10.0.2.2`,
  `192.168.x.x`, `127.0.0.1`) are compiled out — they are unreachable from a
  real phone and would just fail confusingly.
- **Debug/profile** builds keep the dev fallbacks so `flutter run` still works
  against a laptop backend. Override with `--dart-define=CBLREP_LAN_IP=<pc-ip>`
  and `--dart-define=CBLREP_API_PORT=8000`.
- If a release build is produced with **neither** the define nor an edited
  fallback, the app logs `CBLREP_API_URL was not set at build time` at startup
  and points at a dead sentinel host rather than pretending to work.

Trailing slashes and a trailing `/api` in the value are normalised away, so
`https://host.com`, `https://host.com/` and `https://host.com/api` are equivalent.

## Signing

Release builds are signed with the CBLREP release key:

- Keystore: `android/cblrep-release.jks` (alias `cblrep`)
- Credentials: `android/key.properties`
- Both files are in `android/.gitignore` — **back them up somewhere safe and
  never commit them.** Losing this key means you can never ship an update to an
  already-installed app.

`android/app/build.gradle.kts` creates the `release` signing config only when
`key.properties` exists; otherwise it falls back to the debug key so a fresh
clone can still build for local testing. Only Play/direct-distribution builds
need the real key.

Verify a build:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## Versioning

`version: 1.0.0+1` in `pubspec.yaml` → `versionName` / `versionCode` in the APK.
Bump the build number (`+2`, `+3`, …) for every upload; Android refuses
same-or-lower version codes on update.

## Smaller downloads

```bash
./build_release.sh https://your-api-host.com --split-per-abi
```

Emits per-architecture APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) at roughly a
third of the size each. The universal APK is what to hand out if you are unsure
which devices your users have.

## Artifact location

```
mobile/build/app/outputs/flutter-apk/app-release.apk
```

## Required Android permissions (already in the manifest)

| Permission | Why |
| --- | --- |
| `INTERNET` | All API traffic |
| `ACCESS_NETWORK_STATE` | Connection-type checks before retrying a failed request |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | "Near me" filter on the community map (requested at runtime) |

`android:usesCleartextTraffic="true"` remains in the manifest because the debug
LAN/emulator flow uses plain HTTP; production should be served over HTTPS and
`build_release.sh` refuses an `http://` API URL.