#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CBLREP · pre-defense readiness check
#
# Verifies the pre-defense checklist:
#
#   MariaDB, API, ngrok, APP_URL/rewrite, admin login, mobile APK API URL
#
# Run it from anywhere:
#
#   ./scripts/check-connections.sh
#
# Exit code 0 = every check passed. Non-zero = at least one check failed.
#
# Override the console origin for a preview deployment with:
#
#   CONSOLE_URL=https://<deployment>.vercel.app ./scripts/check-connections.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT/backend"

# The console lives at frontend/ in the tier checkout, but a monorepo clone
# nested inside frontend/ keeps it at frontend/frontend/. Support both.
FRONTEND_DIR="$ROOT/frontend"
if [[ ! -f "$FRONTEND_DIR/package.json" && -f "$FRONTEND_DIR/frontend/package.json" ]]; then
  FRONTEND_DIR="$FRONTEND_DIR/frontend"
fi

CONSOLE_URL="${CONSOLE_URL:-https://cblrep-frontend.vercel.app}"
LOCAL_API="${LOCAL_API:-http://127.0.0.1:8000}"
NGROK_HEADER="ngrok-skip-browser-warning: true"
MOBILE_APK="${MOBILE_APK:-$ROOT/storage/backups/app-release-ngrok.apk}"

failures=0
fixes=()

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() {
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  failures=$((failures + 1))
  [[ -n "${2:-}" ]] && fixes+=("$2")
}
info() { printf '        %s\n' "$1"; }

env_value() {
  # env_value FILE KEY — last assignment wins, surrounding quotes stripped.
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^[[:space:]]*${key}=" "$file" | tail -n 1 \
    | cut -d= -f2- | sed -E "s/^[\"']//; s/[\"']$//" | tr -d '\r'
}

ADMIN_CHECK_EMAIL="${ADMIN_CHECK_EMAIL:-$(env_value "$BACKEND_DIR/.env" ADMIN_SEED_EMAIL)}"
ADMIN_CHECK_PASSWORD="${ADMIN_CHECK_PASSWORD:-$(env_value "$BACKEND_DIR/.env" ADMIN_SEED_PASSWORD)}"
ADMIN_CHECK_TOTP="${ADMIN_CHECK_TOTP:-}"

http_code() {
  local url="$1" timeout="${2:-8}" code
  shift 2
  # curl prints 000 itself when it cannot connect; do not append another.
  code="$(curl -sS -o /dev/null -m "$timeout" -w '%{http_code}' "$@" "$url" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

json_field() {
  php -r '$json = json_decode(stream_get_contents(STDIN), true); $value = $json[$argv[1]] ?? ""; if (is_string($value)) echo $value;' "$1"
}

echo
echo "CBLREP pre-defense checklist · $(date '+%Y-%m-%d %H:%M:%S')"
echo "──────────────────────────────────────────────────────────────"
echo "Required: DB up · API up · tunnel up · rewrite matches · admin login · mobile APK URL"

APP_URL="$(env_value "$BACKEND_DIR/.env" APP_URL)"
APP_HOST="$(printf '%s' "$APP_URL" | sed -E 's#^https?://##; s#/.*$##')"

# 1 ── Database ───────────────────────────────────────────────────────────────
if command -v php >/dev/null 2>&1 && [[ -f "$BACKEND_DIR/artisan" ]]; then
  db_out="$(cd "$BACKEND_DIR" && php artisan migrate:status 2>&1)"
  pending="$(printf '%s' "$db_out" | grep -c 'Pending' || true)"
  if printf '%s' "$db_out" | grep -qE 'Migration name|Ran|Pending'; then
    if [[ "$pending" -eq 0 ]]; then
      pass "MariaDB · migrations are current"
    else
      fail "MariaDB · $pending pending migration(s)" "cd backend && php artisan migrate"
    fi
  else
    fail "MariaDB · cannot read migration status" "cd backend && php artisan migrate:status"
    info "$(printf '%s' "$db_out" | tail -n 1)"
  fi
else
  fail "MariaDB · php or backend/artisan not found"
fi

# 2 ── Tunnel configuration: APP_URL must match the Vercel rewrite ────────────
REWRITE_URL=""
if [[ -f "$FRONTEND_DIR/vercel.json" ]]; then
  REWRITE_URL="$(grep -oE 'https://[a-z0-9.-]+/api/:path\*' "$FRONTEND_DIR/vercel.json" | head -n 1 | sed -E 's#/api/:path\*$##')"
fi

if [[ -n "$REWRITE_URL" && -n "$APP_HOST" ]]; then
  if [[ "${REWRITE_URL#https://}" == "$APP_HOST" ]]; then
    pass "Config · backend APP_URL matches the Vercel /api rewrite ($APP_HOST)"
  else
    fail "Config · Vercel rewrite points at ${REWRITE_URL#https://}, backend APP_URL is $APP_HOST" \
      "update frontend/vercel.json → rewrites[0].destination, then redeploy on Vercel"
  fi
elif [[ -z "$REWRITE_URL" ]]; then
  fail "Config · no /api rewrite host found in frontend/vercel.json" \
    "restore the Vercel /api rewrite or update this check for direct-API wiring"
fi

# 3 ── Local API ──────────────────────────────────────────────────────────────
code="$(http_code "$LOCAL_API/api/platform/status" 5)"
if [[ "$code" == "200" ]]; then
  pass "Local API · $LOCAL_API/api/platform/status → 200"
else
  fail "Local API · $LOCAL_API is not answering (HTTP $code)" \
    "cd backend && php artisan serve --host=127.0.0.1 --port=8000"
fi

# 4 ── Public tunnel ──────────────────────────────────────────────────────────
if [[ -z "$APP_URL" ]]; then
  fail "Tunnel · APP_URL is missing from backend/.env"
else
  body="$(curl -sS -m 10 -H "$NGROK_HEADER" -w '\n%{http_code}' "$APP_URL/api/platform/status" 2>/dev/null || printf '\n000')"
  code="${body##*$'\n'}"
  payload="${body%$'\n'*}"
  if [[ "$code" == "200" && "$payload" == \{* ]]; then
    pass "Tunnel · $APP_HOST/api/platform/status → 200"
  elif printf '%s' "$payload" | grep -q 'ERR_NGROK_3200'; then
    fail "Tunnel · $APP_HOST is offline (ERR_NGROK_3200)" \
      "./scripts/dev-tunnel.sh        # pins ngrok to the APP_URL in backend/.env"
  elif [[ "$code" == "000" ]]; then
    fail "Tunnel · $APP_HOST did not answer" "./scripts/dev-tunnel.sh"
  else
    fail "Tunnel · $APP_HOST answered HTTP $code without JSON" "./scripts/dev-tunnel.sh"
  fi
fi

# 5 ── Admin credentials and second-factor login ──────────────────────────────
if [[ -z "$ADMIN_CHECK_EMAIL" || -z "$ADMIN_CHECK_PASSWORD" ]]; then
  fail "Admin login · set ADMIN_CHECK_EMAIL and ADMIN_CHECK_PASSWORD (or ADMIN_SEED_* in backend/.env)"
else
  admin_form="$(ADMIN_FORM_EMAIL="$ADMIN_CHECK_EMAIL" ADMIN_FORM_PASSWORD="$ADMIN_CHECK_PASSWORD" \
    php -r 'echo http_build_query(["email" => getenv("ADMIN_FORM_EMAIL"), "password" => getenv("ADMIN_FORM_PASSWORD")]);')"
  login_response="$(printf '%s' "$admin_form" | curl -sS -m 10 \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-binary @- -w '\n%{http_code}' "$LOCAL_API/api/admin-login" 2>/dev/null || printf '\n000')"
  login_code="${login_response##*$'\n'}"
  login_payload="${login_response%$'\n'*}"
  access_token=""

  if [[ "$login_code" == "200" ]]; then
    challenge="$(printf '%s' "$login_payload" | json_field challenge_token)"
    access_token="$(printf '%s' "$login_payload" | json_field access_token)"

    if [[ -n "$challenge" ]]; then
      if [[ -z "$ADMIN_CHECK_TOTP" && -t 0 ]]; then
        read -r -s -p "Current admin TOTP code (not echoed): " ADMIN_CHECK_TOTP
        printf '\n'
      fi

      if [[ -z "$ADMIN_CHECK_TOTP" ]]; then
        fail "Admin login · password accepted, but TOTP is needed to verify the admin route" \
          "rerun with ADMIN_CHECK_TOTP set, or enter the code when prompted"
      else
        verify_form="$(ADMIN_CHALLENGE="$challenge" ADMIN_TOTP="$ADMIN_CHECK_TOTP" \
          php -r 'echo http_build_query(["challenge_token" => getenv("ADMIN_CHALLENGE"), "code" => getenv("ADMIN_TOTP")]);')"
        verify_response="$(printf '%s' "$verify_form" | curl -sS -m 10 \
          -H 'Accept: application/json' \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data-binary @- -w '\n%{http_code}' "$LOCAL_API/api/admin/2fa/verify" 2>/dev/null || printf '\n000')"
        verify_code="${verify_response##*$'\n'}"
        verify_payload="${verify_response%$'\n'*}"
        if [[ "$verify_code" == "200" ]]; then
          access_token="$(printf '%s' "$verify_payload" | json_field access_token)"
        fi
      fi
    elif [[ -z "$access_token" ]]; then
      fail "Admin login · account needs 2FA enrollment before an admin session can be verified" \
        "complete administrator 2FA enrollment, then rerun this check"
    fi

    if [[ -n "$access_token" ]]; then
      code="$(http_code "$LOCAL_API/api/admin/users" 8 -H "Authorization: Bearer $access_token")"
      if [[ "$code" == "200" ]]; then
        pass "Admin login · credentials and admin API access verified"
        curl -sS -m 5 -X POST -H "Authorization: Bearer $access_token" \
          "$LOCAL_API/api/logout" >/dev/null 2>&1 || true
      else
        fail "Admin login · credentials passed, but /api/admin/users returned HTTP $code"
      fi
    elif [[ -n "$challenge" && -n "$ADMIN_CHECK_TOTP" ]]; then
      fail "Admin login · second-factor verification failed (HTTP ${verify_code:-000})" \
        "check the current TOTP code and try again"
    fi
  else
    fail "Admin login · primary credentials rejected (HTTP $login_code)" \
      "check ADMIN_CHECK_EMAIL and ADMIN_CHECK_PASSWORD; do not print them in shared logs"
  fi
fi

# 6 ── The installed mobile APK must target the current tunnel ────────────────
if [[ ! -f "$MOBILE_APK" ]]; then
  fail "Mobile build · APK not found at $MOBILE_APK" \
    "download app-release-ngrok.apk and set MOBILE_APK=/path/to/app-release-ngrok.apk"
elif ! command -v unzip >/dev/null 2>&1 || ! command -v strings >/dev/null 2>&1; then
  fail "Mobile build · unzip and strings are required to inspect the APK"
else
  mobile_match="$(unzip -p "$MOBILE_APK" 'lib/*/libapp.so' 2>/dev/null \
    | strings | grep -F "$APP_HOST" | head -n 1 || true)"
  if [[ -n "$APP_HOST" && -n "$mobile_match" ]]; then
    pass "Mobile build · $MOBILE_APK contains the current tunnel host ($APP_HOST)"
  else
    fail "Mobile build · API host in $MOBILE_APK does not match APP_URL ($APP_HOST)" \
      "rebuild with ./build_release.sh $APP_URL and install app-release-ngrok.apk"
  fi
fi

# 7 ── Deployed console ───────────────────────────────────────────────────────
code="$(http_code "$CONSOLE_URL/" 12)"
if [[ "$code" == "200" ]]; then
  pass "Console · $CONSOLE_URL/ → 200"
else
  fail "Console · $CONSOLE_URL/ → HTTP $code" "check the Vercel deployment"
fi

code="$(http_code "$CONSOLE_URL/api/platform/status" 12 -H "$NGROK_HEADER")"
if [[ "$code" == "200" ]]; then
  pass "Console → API · $CONSOLE_URL/api/platform/status → 200"
else
  fail "Console → API · HTTP $code (the console cannot sign in)" \
    "./scripts/dev-tunnel.sh        # the rewrite target must be online"
fi

echo "──────────────────────────────────────────────────────────────"
if [[ "$failures" -eq 0 ]]; then
  printf '\033[32mPASS: all pre-defense checks passed\033[0m\n'
  exit 0
fi

printf 'Fixes for the %d failed check(s):\n' "$failures"
if [[ "${#fixes[@]}" -gt 0 ]]; then
  printf '%s\n' "${fixes[@]}" | awk '!seen[$0]++ { print "  " $0 }'
fi
printf '\033[31mFAIL: %d pre-defense check(s) failed\033[0m\n' "$failures"
exit 1
