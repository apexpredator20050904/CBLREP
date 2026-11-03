#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CBLREP · start the ngrok tunnel on the address the project already expects
#
#   ./scripts/dev-tunnel.sh            # forwards http://127.0.0.1:8000
#   ./scripts/dev-tunnel.sh 8001       # custom local port
#
# Why this exists: frontend/vercel.json hardcodes the tunnel host in its /api
# rewrite (Vercel cannot read env vars from a rewrite), and backend/.env's
# APP_URL must name the same host. A plain `ngrok http 8000` may claim a
# different free-tier subdomain, silently breaking the deployed console.
# This script reads the host from backend/.env and pins ngrok to it with
# `--url`, so one value — APP_URL — drives both sides.
#
# Keep the API running in another terminal:
#   cd backend && php artisan serve --host=127.0.0.1 --port=8000
#
# Then confirm the whole chain:
#   ./scripts/check-connections.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/backend/.env"
PORT="${1:-8000}"

if ! command -v ngrok >/dev/null 2>&1; then
  echo "error: ngrok is not installed or not on PATH." >&2
  echo "       install it, then: ngrok config add-authtoken <token>" >&2
  exit 1
fi

APP_URL=""
if [[ -f "$ENV_FILE" ]]; then
  APP_URL="$(grep -E '^[[:space:]]*APP_URL=' "$ENV_FILE" | tail -n 1 \
    | cut -d= -f2- | sed -E "s/^[\"']//; s/[\"']$//" | tr -d '\r')"
fi
APP_HOST="$(printf '%s' "$APP_URL" | sed -E 's#^https?://##; s#/.*$##')"

echo "CBLREP · ngrok tunnel"
echo "  local target : http://127.0.0.1:$PORT"

if [[ "$APP_HOST" == *.ngrok-free.app || "$APP_HOST" == *.ngrok-free.dev \
      || "$APP_HOST" == *.ngrok.app || "$APP_HOST" == *.ngrok.io ]]; then
  echo "  pinned URL   : https://$APP_HOST"
  echo "  (from backend/.env APP_URL; the Vercel /api rewrite expects this host)"
  echo
  # exec so Ctrl-C stops ngrok directly.
  exec ngrok http "$PORT" --url "https://$APP_HOST"
fi

echo "  pinned URL   : none"
if [[ -n "$APP_HOST" ]]; then
  echo "  warning      : APP_URL is '$APP_HOST', not an ngrok host." >&2
else
  echo "  warning      : APP_URL is missing from backend/.env." >&2
fi
echo "  ngrok will pick a random free-tier subdomain, and the deployed console"
echo "  will keep pointing at the host hardcoded in frontend/vercel.json."
echo "  Set APP_URL to that reserved ngrok URL to pin the tunnel instead."
echo
exec ngrok http "$PORT"
