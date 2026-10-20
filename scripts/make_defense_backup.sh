#!/usr/bin/env bash
#
# Assemble the CBLREP capstone-defense backup package.
#
# Produces, under storage/backups/:
#
#   cblrep-db-<date>.sql                     MySQL schema + seeded data
#   app-release.apk                          the signed, tunnel-pointed APK
#   cblrep-defense-<date>.tar.gz             SHAREABLE bundle — all three tiers
#                                            (with .git history), the DB dump,
#                                            the APK, and the project docs
#   cblrep-defense-<date>-SECRETS.tar.gz     PRIVATE — backend/.env + the Android
#                                            signing key. Never upload this to a
#                                            shared drive.
#   SHA256SUMS                               integrity hashes for the above
#
# Heavy, reproducible directories (vendor/, node_modules/, .dart_tool/,
# mobile/build/ intermediates) are excluded; the compiled APK is included
# explicitly. Run from anywhere:
#
#   ./scripts/make_defense_backup.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
STAMP="$(date +%F-%H%M)"
OUT="$ROOT/storage/backups"
mkdir -p "$OUT"

DB_NAME="community-based-portal"
DB_USER="cblrep"
DB_PASS="$(grep '^DB_PASSWORD=' backend/.env | cut -d= -f2-)"

DUMP_NAME="cblrep-db-${STAMP}.sql"
DUMP="$OUT/$DUMP_NAME"
APK_SRC="mobile/build/app/outputs/flutter-apk/app-release.apk"
APK_DST="$OUT/app-release.apk"
PKG="$OUT/cblrep-defense-${STAMP}.tar.gz"
SECRETS="$OUT/cblrep-defense-${STAMP}-SECRETS.tar.gz"
SUMS="$OUT/SHA256SUMS"

echo "==> 1/4  Dumping MySQL '$DB_NAME'"
mysqldump -u "$DB_USER" -p"$DB_PASS" \
  --single-transaction --routines --triggers --events \
  --default-character-set=utf8mb4 \
  "$DB_NAME" > "$DUMP"

echo "==> 2/4  Copying release APK"
if [[ -f "$APK_SRC" ]]; then
  cp -f "$APK_SRC" "$APK_DST"
else
  echo "    WARNING: $APK_SRC not found — build the APK first." >&2
fi

echo "==> 3/4  Packing shareable bundle"
tar -czf "$PKG" \
  --exclude="storage/backups/${PKG##*/}" \
  --exclude='storage/backups/*.tar.gz' \
  --exclude='storage/backups/*.git' \
  --exclude='backend/vendor' \
  --exclude='backend/node_modules' \
  --exclude='backend/.env' \
  --exclude='backend/storage/logs/*' \
  --exclude='backend/storage/framework/cache/*' \
  --exclude='backend/storage/framework/sessions/*' \
  --exclude='backend/storage/framework/views/*' \
  --exclude='backend/storage/framework/testing' \
  --exclude='frontend/node_modules' \
  --exclude='frontend/dist' \
  --exclude='frontend/.env' \
  --exclude='mobile/.dart_tool' \
  --exclude='mobile/build' \
  --exclude='mobile/android/build' \
  --exclude='mobile/android/.gradle' \
  --exclude='mobile/.flutter-plugins*' \
  --exclude='*/ephemeral' \
  --exclude='*.log' \
  --exclude='key.properties' \
  --exclude='*.jks' \
  --exclude='*.keystore' \
  --exclude='local.properties' \
  --exclude='backend/.env' \
  --exclude='backend/.env.*' \
  -C "$ROOT" \
  backend frontend mobile storage \
  README.md RUNNING.md DEPLOYMENT.md docs \
  vercel.json .vercelignore scripts

echo "==> 4/4  Packing secrets + writing checksums"

# Guard: the shareable bundle must never contain credentials.
if tar -tzf "$PKG" | grep -qE '(^|/)(\.env|key\.properties)$|\.(jks|keystore)$'; then
  echo "ERROR: secrets detected inside $PKG — refusing to continue." >&2
  exit 1
fi
cat > "$OUT/SECRETS-README.txt" <<'EOF'
CBLREP defense — PRIVATE archive (DO NOT share or upload publicly)

Contents:
  backend/.env                     DB + app credentials, APP_KEY (needed to restore)
  mobile/android/key.properties    Android signing passwords
  mobile/android/cblrep-release.jks Android release keystore

Losing the keystore means you can never update an already-installed app.
Keep this archive in a password-protected location only.
EOF
tar -czf "$SECRETS" \
  -C "$ROOT" \
  backend/.env mobile/android/key.properties mobile/android/cblrep-release.jks \
  -C "$OUT" SECRETS-README.txt

( cd "$OUT" && sha256sum "$DUMP_NAME" app-release.apk "${PKG##*/}" "${SECRETS##*/}" > "$SUMS" 2>/dev/null || true )

echo
echo "==> Done. Artifacts in $OUT:"
ls -lh "$OUT" | grep -vE '^total' || true
echo
echo "Shareable bundle : ${PKG##*/}"
echo "Secrets (private): ${SECRETS##*/}"
