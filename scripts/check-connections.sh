#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CBLREP · end-to-end connection check
#
# Verifies the whole chain the project depends on:
#
#   MariaDB ← Laravel API (:8000) ← ngrok tunnel ← Vercel console
#
# Run it from anywhere:
#
#   ./scripts/check-connections.sh
#
# Exit code 0 = every link answered. Non-zero = at least one link is down;
# each failure is printed with the command that fixes it.
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

http_code() {
  local url="$1" timeout="${2:-8}" code
  shift 2
  # curl prints 000 itself when it cannot connect; do not append another.
  code="$(curl -sS -o /dev/null -m "$timeout" -w '%{http_code}' "$@" "$url" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

echo
echo "CBLREP connection check · $(date '+%Y-%m-%d %H:%M:%S')"
echo "──────────────────────────────────────────────────────────────"

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
  info "config · no /api rewrite in frontend/vercel.json (console calls the API directly)"
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

# 5 ── Deployed console ───────────────────────────────────────────────────────
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
  printf '\033[32mAll links are up.\033[0m\n\n'
  exit 0
fi

printf '\033[31m%d link(s) down.\033[0m\n' "$failures"
if [[ "${#fixes[@]}" -gt 0 ]]; then
  echo
  echo "Fix:"
  printf '%s\n' "${fixes[@]}" | awk '!seen[$0]++ { print "  " $0 }'
fi
echo
exit 1
