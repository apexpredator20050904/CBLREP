# CBLREP — Member app (Flutter)

The Android app members use to post what they have and what they need, trade
with their neighbours, message each other and follow their listings.

| | |
| --- | --- |
| **Branch** | `flutter-app` — the source of truth for `mobile/` in the monorepo |
| **Stack** | Flutter · Dart 3.12 · Provider |
| **Docs** | [RUNNING.md](https://github.com/apexpredator20050904/CBLREP/blob/main/RUNNING.md) · [BUILD.md](https://github.com/apexpredator20050904/CBLREP/blob/main/mobile/BUILD.md) |

## Run it

```bash
flutter pub get
flutter run -d <device_id> --dart-define=CBLREP_API_URL=https://<subdomain>.ngrok-free.dev
```

The API host is **compiled into the binary**, so it is baked in at build time.
Debug builds probe the candidates in order (`CBLREP_API_URL` → the LAN →
emulator/loopback); a release build honours only the URL it was given.

## Build a distributable APK

```bash
./build_release.sh https://api.cblrep.ph     # or an ngrok subdomain
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release is signed with the keystore in `android/` — see
[BUILD.md](https://github.com/apexpredator20050904/CBLREP/blob/main/mobile/BUILD.md)
for the signing details, and the full runbook is in
[RUNNING.md](https://github.com/apexpredator20050904/CBLREP/blob/main/RUNNING.md).
