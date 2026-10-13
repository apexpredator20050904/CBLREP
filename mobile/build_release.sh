#!/usr/bin/env bash
#
# Build a distributable release APK for the CBLREP Flutter app.
#
# The production API host is compiled INTO the binary via --dart-define, so it
# must be passed here. With no argument the script refuses to build rather than
# shipping an APK that cannot reach any backend.
#
#   ./build_release.sh https://cblrep-api.onrender.com
#
# Options:
#   --split-per-abi   also emit per-architecture APKs (smaller downloads)
#   --skip-clean      skip `flutter clean` (faster iteration)
#
set -euo pipefail

cd "$(dirname "$0")"

API_URL="${1:-}"
shift || true

if [[ -z "$API_URL" ]]; then
  cat <<'EOF'
Usage: ./build_release.sh <PRODUCTION_API_URL> [--split-per-abi] [--skip-clean]

  <PRODUCTION_API_URL>  Public origin of the Laravel API, e.g.
                        https://cblrep-api.onrender.com
                        (no trailing slash; "/api" is appended automatically)

The URL is baked into the APK with:
  --dart-define=CBLREP_API_URL=<url>
EOF
  exit 1
fi

# Strip trailing slashes / a trailing /api so the value is a clean origin.
API_URL="${API_URL%/}"
API_URL="${API_URL%/api}"
[[ "$API_URL" == http://* ]] && {
  echo "ERROR: release builds must use https:// — Android blocks cleartext to" >&2
  echo "       remote hosts. Use your production TLS origin." >&2
  exit 1
}

SPLIT=""
for arg in "$@"; do
  case "$arg" in
    --split-per-abi) SPLIT="--split-per-abi" ;;
    --skip-clean)    SKIP_CLEAN=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ -z "${SKIP_CLEAN:-}" ]]; then
  echo "==> flutter clean"
  flutter clean
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build apk --release  (API: $API_URL/api)"
flutter build apk --release \
  --dart-define=CBLREP_API_URL="$API_URL" \
  $SPLIT

echo
echo "==> Artifacts"
ls -lh build/app/outputs/flutter-apk/*.apk
echo
echo "Verify the baked-in host with:"
echo "  strings build/app/outputs/flutter-apk/app-release.apk | grep -o 'https://[^ ]*api' | head"