# CBLREP — Developer Guide

Complete setup, run and test instructions for all three tiers of the
Community-Based Local Resources Exchange Portal.

| Tier | Path | Stack |
| --- | --- | --- |
| Backend API | `backend/` | Laravel 12 · PHP 8.2+ · Sanctum 4 · MariaDB/MySQL |
| Admin console | `frontend/` | React 19 · Vite 8 · Tailwind 4 · Leaflet |
| Mobile app | `mobile/` | Flutter 3.x · Dart 3.12+ · Provider |

Companion docs: `DEPLOYMENT.md` (Vercel), `mobile/BUILD.md` (release signing),
`backend/deploy/DEPLOY_DEBIAN.md` (production nginx/PHP-FPM runbook).

---

## 1. System Requirements & Prerequisites

| Tool | Required | Notes |
| --- | --- | --- |
| PHP | **8.2+** (8.3 verified) | Needs `pdo_mysql`, `mbstring`, `openssl`, `tokenizer`, `xml`, `curl`, `fileinfo` |
| Composer | **2.x** | Dependency install for Laravel |
| MySQL / MariaDB | **10.11+ / 8.0+** | Must be running before migrations (bind to loopback) |
| Node.js | **20+** (22 verified) | Vite 8 requires modern Node |
| npm | **10+** | Ships with Node |
| Flutter SDK | **3.35+** (3.47.5 verified) | Stable channel |
| Dart | **3.12+** | Bundled with Flutter |
| JDK | **17+** (21 recommended) | Android Gradle Plugin requirement |
| Android SDK | **API 36 / compileSdk 36** | Platform + build-tools; SDK path in `android/local.properties` |
| ADB | Any recent | Inside `platform-tools/` |
| **ngrok** | **any recent** | Public HTTPS tunnel so the mobile app + the whole stack work off your LAN; free tier is fine for a single session |

**Verify everything at once:**

```bash
php -v && composer --version && node -v && npm -v
mysql --version && systemctl is-active mariadb     # or: brew services list
flutter --version && flutter doctor
adb version && adb devices
ngrok --version
```

`flutter doctor` should show `[✓] Flutter` and `[✓] Android toolchain`.
A `[!]` on the Android toolchain means the SDK path is unset — see §7.5.

---

## 2. Backend Setup & Local Server (Laravel API)

### 2.1 Install dependencies

```bash
cd backend
composer install
```

### 2.2 Environment file

```bash
cp .env.example .env      # only if .env is missing
php artisan key:generate --force
```

The API is stateless (Sanctum **bearer tokens**, not sessions), so
`php artisan key:generate` is required but `php artisan passport:*` is not —
no Passport keys step exists in this project.

Verify the database block in `backend/.env`:

```dotenv
APP_URL=https://<your-ngrok-subdomain>.ngrok-free.dev     # ngrok HTTPS tunnel URL, the default for local dev
APP_DEBUG=true                                           # false in production

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=community-based-portal
DB_USERNAME=cblrep
DB_PASSWORD=your_password

FILESYSTEM_DISK=local
MAIL_MAILER=log
```

Fill in your ngrok subdomain in `APP_URL`. The tunnel URL is your single,
publicly reachable host for the whole project — API, admin console and mobile
app all point at it. (The production Debian/nginx runbook uses
`https://api.cblrep.ph` instead; see `backend/deploy/DEPLOY_DEBIAN.md`).

### 2.3 Create the database

```bash
mysql -u root -p
```

```sql
CREATE DATABASE community-based-portal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'cblrep'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON community-based-portal.* TO 'cblrep'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 2.4 Migrate and seed

```bash
php artisan migrate --force        # 49 migrations
php artisan migrate:status         # confirm everything is "Ran"

# Destructive: truncates EVERY table, then creates only the super admin.
php artisan db:seed --force
```

**Seeded super admin** — created by `backend/database/seeders/DatabaseSeeder.php`,
which also enrols TOTP 2FA and prints the secret plus one-time recovery codes
to the console:

```
Email:    admin@cblrep.ph
Password: adminpass123
```

> Change this password immediately outside local development. Re-running
> `db:seed` wipes all data (users, listings, messages, conversations) and
> re-creates only this account.

**Optional demo data** — additive and idempotent, never deletes anything:

```bash
php artisan db:seed --class=DemoSeeder
```

Creates the category set, listings, barter proposals, conversations and four
member accounts (`maria.santos@cblrep.test`, `pedro.reyes@cblrep.test`,
`ana.delacruz@cblrep.test`, `jose.lim@cblrep.test` — all with password
`Demo@1234`).

### 2.5 Link uploaded media

```bash
php artisan storage:link
```

Listing photos are served from `public/storage`. If images 404, this symlink
is the reason.

### 2.6 Run the server over the LAN

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

`--host=0.0.0.0` is mandatory — the default `127.0.0.1` is unreachable from a
phone on the same Wi-Fi.

**Health check:**

```bash
curl http://127.0.0.1:8000/api/platform/status
curl http://<YOUR_LAN_IP>:8000/api/platform/status   # must also return 200
```

The second command is the one that matters: if it fails, the phone will not be
able to reach the API.

**Attachment uploads (chat photos / documents / video).** The CLI PHP config
(`/etc/php/8.3/cli/php.ini`) caps uploads at **2 MB**, which silently rejects
larger chat attachments before Laravel ever sees them. `php artisan serve`
cannot forward ini overrides to the built-in server it spawns, so raise the
limits by launching that server directly instead:

```bash
cd public
php -d upload_max_filesize=64M -d post_max_size=68M \
  -S 0.0.0.0:8000 ../vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php
```

`post_max_size` must be larger than `upload_max_filesize` (multipart framing
overhead). Chat attachments are accepted up to **50 MB** (photos/documents are
guarded at 10 MB in the app UI; video up to 50 MB, 1-minute clips). Editing
`/etc/php/8.3/cli/php.ini` directly (needs root) works too.

### 2.7 Expose the backend with ngrok

`php artisan serve` binds to your machine only. To reach the API from a phone
on any network — or from any browser outside your LAN — put a public HTTPS
tunnel in front of port 8000:

```bash
ngrok http 8000
```

Install, authtoken, and every place the generated URL must be updated are in
**§5 Ngrok Tunneling Setup**.

---

## 3. Admin Panel Setup (React + Vite)

### 3.1 Install and configure

```bash
cd frontend
npm install
cp .env.example .env
```

```dotenv
# Leave EMPTY for local dev — requests stay same-origin and the Vite dev
# server proxies /api to the backend, so no CORS preflight is needed.
VITE_API_BASE_URL=

# Where that dev proxy forwards /api/*. Use 127.0.0.1 (not your LAN IP) —
# the proxy runs on this machine.
VITE_API_TARGET=http://127.0.0.1:8000
```

On **Vercel** this is inverted: set `VITE_API_BASE_URL` to the public API origin
and leave `VITE_API_TARGET` unset. See `DEPLOYMENT.md`.

### 3.2 Development

```bash
npm run dev
```

Vite binds `0.0.0.0:5173`, so other devices on the LAN can load the console too.

### 3.3 Production build verification

```bash
npm run check      # lint + build, the same gate CI/Vercel runs
npm run build      # build only
npm run start      # serve ./dist locally on :4173
```

`npm run check` must report **0 ESLint problems**. Hard-refresh
`http://localhost:4173/admin/listings` afterwards to confirm the SPA rewrite
behaves.

---

## 4. Mobile App Setup & Device Deployment (Flutter)

### 4.1 Dependencies

```bash
cd mobile
flutter clean
flutter pub get
```

### 4.2 Find your LAN IP

The app cannot reach `localhost` on your PC. Every `--dart-define` below needs
this address (with an ngrok tunnel you can skip the LAN IP entirely — §6.2):

```bash
hostname -I | awk '{print $1}'     # e.g. 192.168.1.81
```

Update `frontend/.env`'s `VITE_API_TARGET` and `backend/.env`'s `APP_URL` to
match whenever the IP changes.

### 4.3 Connect the device

```bash
adb devices -l
```

Expected: `R9WWB0S5GMH  device  usb:1-3  model:SM_A146P`.

On the phone: **Settings → Developer options → USB debugging ON**, then accept
the **"Allow USB debugging?"** prompt. Samsung also has *USB debugging (Security
settings)* — enable it if installs fail.

### 4.4 Run on the physical device

```bash
flutter run -d R9WWB0S5GMH --dart-define=CBLREP_API_URL=http://192.168.1.81:8000
```

Hot reload (`r`) and hot restart (`R`) work normally. The phone must be on the
**same Wi-Fi** as the PC.

**The three base-URL modes** (`mobile/lib/core/api_service.dart`):

| Build | Resolution order |
| --- | --- |
| Release | `CBLREP_API_URL` **only** — emulator/LAN/loopback candidates are compiled out |
| Debug / profile | `CBLREP_API_URL`, then LAN (`CBLREP_LAN_IP`), then emulator `10.0.2.2` / loopback |
| Release without the define | Points at a dead sentinel host and logs a warning at startup |

Because the URL is inlined at compile time, **changing it requires a rebuild**.

### 4.5 Release APK for manual installation

Signing keys live at `mobile/android/cblrep-release.jks` + `key.properties`
(both git-ignored). The helper script refuses to build without a URL:

```bash
cd mobile
./build_release.sh https://api.your-domain.com     # production
./build_release.sh http://192.168.1.81:8000        # LAN testing
./build_release.sh https://api.example.com --split-per-abi   # smaller APKs
```

Manual build, without the helper:

```bash
flutter build apk --release \
  --dart-define=CBLREP_API_URL=https://api.your-domain.com
```

Artifact: `mobile/build/app/outputs/flutter-apk/app-release.apk`

Install it directly:

```bash
adb install -r mobile/build/app/outputs/flutter-apk/app-release.apk
```

Verify the signature:

```bash
apksigner verify --print-certs mobile/build/app/outputs/flutter-apk/app-release.apk
```

**Google Maps key** (only needed for the map screen). Resolution order is
`-PMAPS_API_KEY=…`, then `mapsApiKey=` in `android/local.properties`, then an
empty fallback:

```bash
# mobile/android/local.properties
mapsApiKey=YOUR_GOOGLE_MAPS_KEY
```

### 4.6 Tests

```bash
cd mobile
flutter analyze          # expect no errors or warnings
flutter test             # layout regression tests for cards, detail view, dropdowns
```

---

### 4.7 Barter creation UI

`POST /api/barter-proposals` and `POST /api/exchanges` are implemented and
validated on the backend, and the **mobile app now calls them**: the trade
offer sheet (`mobile/lib/widgets/trade_offer_sheet.dart`) is opened from a
listing's "Make a trade offer" button and from the "Propose Barter" action on
a feed card. It collects the return side (one of your own listings, or a
description of a skill) and the handover point, and the owner answers it in
the Exchanges tab.

`POST /api/barter-proposals` and `POST /api/exchanges` are the same endpoint —
one table, one state machine.

### 4.7b Offers and needs are the same listing from opposite ends

A listing is either an **OFFER** ("I have this") or a **NEED** ("I want
this"), and every shared column is read from the matching side:

| | **Offer** | **Need** |
| --- | --- | --- |
| `price` | the asking price | the poster's **budget ceiling** |
| `wanted_item` | what the owner wants back | what the poster can trade |
| `condition` | the item's state | what the poster can accept |
| photos | of the item | references of the thing wanted |
| `quantity` | — | how much is needed ("5 kg") |

The API publishes which reading applies, so no client has to guess:

```json
{ "price_role": "budget", "wanted_item_role": "offers_in_return",
  "condition_role": "acceptable_condition", "images_role": "reference_photos" }
```

Two rules the backend enforces:

- **A need cannot be free.** "I need this, free" is not a want ad — posting
  a gift is what an *offer* with Free is for. A need is answered with a
  trade or a payment. (`POST /api/listings` answers `422`.)
- **The direction is immutable.** A listing's `type` cannot change after
  posting, because flipping it would invert every shared column and
  invalidate the proposals already attached to it.

Answering a need mirrors the roles of a trade, on the same `exchanges` table:

| | Offer | Need |
| --- | --- | --- |
| the proposer is | the **demander** | the **supplier** ("I have this") |
| `provider_id` | the listing owner | the proposer |
| `receiver_id` | the proposer | the listing owner |
| accepts the proposal | the owner | the owner (the poster) |

The accept authority is therefore "the owner of the listing", never "the
provider" — on a need the poster decides whether to take what is being
brought. The dual confirmation becomes the handover receipt (supplier: "I
handed it over"; poster: "I received it"), and the need closes when both have
confirmed.

A **paid** need is not answered through the exchanges table: money has no
return side, so the app opens the listing's chat thread with a price quote
instead (`POST /api/exchanges` answers `422` for a paid need).

**The return side of a supply belongs to the poster.** The server writes the
poster's own `wanted_item` into the row, so a supplier cannot put different
terms on the record than the poster actually made — the trade always states
the poster's terms, and any variation is settled in chat. A poster who named
**no** return side leaves the supplier free to bring the item and ask for
nothing: "I need this, no strings attached" is a legitimate want ad, so that
supply is one-sided (`offered` reads *"Nothing asked in return"*). The
one-sided rule that protects a **trade** is untouched — a trade still needs
both sides, which is what stops a proposer turning a gift into a barter.

**A listing's direction is immutable.** Flipping an offer into a need would
invert every shared column and invalidate the proposals already attached, so
`PATCH /api/listings/{id}` answers `422` when the direction changes. The
aliases `need` and `needs` are accepted and land on the same row as
`request`.

**A conversation can only be opened on a listing that is still visible.** An
archived, traded or moderator-held listing is off the feed, and the chat door
used to be the way around that — a member who knew the id could open a thread
about a removed listing and the owner was still notified. `POST
/api/conversations` now answers `404` for anything that is not live.


### 4.8 Public listings feed is paginated

`GET /api/listings` returns 30 per page by default (`?per_page=`, max 100) and
includes a `meta` block:

```json
{ "listings": [...], "data": [...], "meta": { "current_page": 1, "total": 128, "has_more": true } }
```

`data` is a legacy alias of `listings`, kept so existing mobile builds that
read the old key keep working. The endpoint is throttled to 300 requests per
minute per IP — a client polling hard will receive HTTP 429. The budget is
per-IP because the feed is unauthenticated, and a barangay's members often
share one router address (a mobile carrier's CGNAT puts hundreds of
subscribers behind a single IP), so it is set to leave room for a shared
address.

---

## 5. Ngrok Tunneling Setup

ngrok gives the whole stack one public HTTPS host, so the phone app, a
classmate's laptop or the Vercel-hosted console can reach your machine from
**any** network — no Wi-Fi tethering, no port forwarding.

### 5.1 Install and authenticate (once)

```bash
# Linux (this machine: ~/.local/bin/ngrok)
sudo snap install ngrok
# …or download the binary from https://ngrok.com/download and put it on PATH

ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>   # free account, one time
ngrok --version                                     # 3.x verified (3.39.11)
```

### 5.2 Start the backend, then the tunnel

Terminal 1 — Laravel:

```bash
cd backend
php artisan serve --host=127.0.0.1 --port=8000
```

Terminal 2 — tunnel:

```bash
cd backend
ngrok http 8000
```

```text
Forwarding  https://<subdomain>.ngrok-free.dev -> http://127.0.0.1:8000
```

Verify through the public URL (this is the URL clients will use):

```bash
curl https://<subdomain>.ngrok-free.dev/api/platform/status
```

- Keep **both** terminals open — closing either kills the endpoint.
- On the free tier the subdomain changes every restart (reserve one on the
  ngrok dashboard to keep it stable).
- If a browser shows ngrok's interstitial page, that is only for HTML
  navigations; API calls with `Accept: application/json` pass straight through.

### 5.3 Where the ngrok URL must be updated

| # | Location | Set it to | When |
| --- | --- | --- | --- |
| 1 | `backend/.env` → `APP_URL` | `https://<subdomain>.ngrok-free.dev` | **Always.** Drives `asset()` URLs (listing photos) and links — must match the origin clients actually call. Then run `php artisan config:clear`. |
| 2 | Flutter `--dart-define=CBLREP_API_URL` (or `./build_release.sh <url>`) | the same URL, no trailing slash (`/api` is appended automatically) | Every `flutter run` / APK build once the host changes — the URL is **compiled into the binary**. |
| 3 | `frontend/.env` → `VITE_API_BASE_URL` | **leave empty** for `npm run dev` | Never changes for local dev: requests stay same-origin and the Vite proxy forwards them to `VITE_API_TARGET=http://127.0.0.1:8000`, which keeps working while the tunnel is up. |
| 4 | `backend/config/cors.php` | **no edit needed** | ngrok hostnames are already allowed by `allowed_origins_patterns` (`*.ngrok-free.app`, `*.ngrok-free.dev`, `*.ngrok.app`, `*.ngrok.io`). |
| 5 | `backend/.env` → `APP_APK_URL` / `APP_APK_SHA256` | **leave empty** on a dev/ngrok backend | Otherwise `GET /api/app-version` triggers the in-app update prompt pointing at a stale APK. |
| 6 | `backend/.env` → Firebase (`FIREBASE_CREDENTIALS`) | unchanged | Push works over the tunnel as-is. |

After touching `backend/.env`:

```bash
cd backend
php artisan config:clear        # or config:cache if you cache config
```

**Restart checklist when the subdomain changes** (new ngrok session):

1. `backend/.env` → new `APP_URL` + `php artisan config:clear`
2. Rebuild/re-run the Flutter client with the new `CBLREP_API_URL`
   (`flutter run …` or `./build_release.sh https://<subdomain>.ngrok-free.dev`)
3. Web console: nothing to do (it never hardcodes the API origin in dev mode)

### 5.4 Sharing the admin console through ngrok (optional)

```bash
ngrok http 5173     # second tunnel for the Vite dev server
```

The resulting `https://<subdomain>.ngrok-free.dev` origin already matches the
CORS patterns, and the console's `/api` calls still go through the Vite proxy
to `127.0.0.1:8000` — no extra configuration either way.

---

## 6. Running the Clients

The full local loop — four terminals:

```bash
# 1 ── backend
cd backend && php artisan serve --host=127.0.0.1 --port=8000

# 2 ── public tunnel (phones / other machines)
cd backend && ngrok http 8000

# 3 ── admin console (open in this machine's browser)
cd frontend && npm run dev          # http://localhost:5173

# 4 ── mobile app (debug build against the tunnel)
cd mobile
flutter run -d <device_id> --dart-define=CBLREP_API_URL=https://<subdomain>.ngrok-free.dev
```

### 6.1 Web admin dashboard

| Mode | Command | Open at |
| --- | --- | --- |
| Local dev (recommended) | `cd frontend && npm run dev` | `http://localhost:5173` |
| Another device on the LAN | same command — Vite binds `0.0.0.0:5173` | `http://<LAN_IP>:5173` |
| Anywhere via ngrok | `ngrok http 5173` (§5.4) | `https://<subdomain>.ngrok-free.dev` |
| Production bundle, locally | `npm run build && npm run start` | `http://localhost:4173` |

In every local mode `VITE_API_BASE_URL` stays **empty**: requests are relative
`/api/*` and the Vite proxy forwards them to `VITE_API_TARGET`
(`http://127.0.0.1:8000`), so the ngrok URL never has to be configured in the
frontend. Sign in with `admin@cblrep.ph` / `adminpass123` plus the TOTP code
printed by the seeder (§2.4).

### 6.2 Mobile client

| Scenario | Command |
| --- | --- |
| Debug, via ngrok (any network) | `flutter run -d <id> --dart-define=CBLREP_API_URL=https://<subdomain>.ngrok-free.dev` |
| Debug, same Wi-Fi as the PC | `flutter run -d <id> --dart-define=CBLREP_API_URL=http://<LAN_IP>:8000` |
| Debug, USB only (no defines) | `adb reverse tcp:8000 tcp:8000` then `flutter run -d <id>` — the loopback candidate is probed automatically |
| Android emulator | `flutter run -d <emulator_id>` — falls back to `http://10.0.2.2:8000` |
| Installable APK, ngrok host | `./build_release.sh https://<subdomain>.ngrok-free.dev` then `adb install -r build/app/outputs/flutter-apk/app-release.apk` |

Debug builds probe candidates in order (`CBLREP_API_URL` → `CBLREP_LAN_IP` →
emulator/loopback), so the first host that answers
`GET /api/platform/status` wins. Release builds honour **only** the baked-in
URL — rebuild whenever the ngrok host changes (§5.3).

---

## 7. Common Troubleshooting & Network Diagnostics

### 7.1 ADB sees no device

```bash
adb kill-server && adb start-server
adb devices -l
```

The phone must appear in `lsusb` **and** in `adb devices`. If it appears in
`lsusb` but not `adb devices`, the connection is authenticating then dropping:

```bash
dmesg | grep -i "usb 1-1\|cdc_acm" | tail -10
```

Symptoms and causes:

| Log line | Cause | Fix |
| --- | --- | --- |
| `device not accepting address, error -71` | Flaky cable or port | Change cable **and** USB port |
| `USB disconnect` repeating every few seconds | Same | Same |
| Device never enumerates at all | USB debugging off | Enable it, accept the RSA prompt |

On the phone, also try: **Developer options → Revoke USB debugging
authorizations**, toggle USB debugging off/on, then replug.

`sudo` is not needed for a normal USB install. If permissions look wrong:

```bash
ls -l /dev/bus/usb/001/     # expect root:plugdev with your user in plugdev
groups                      # you should see plugdev
```

### 7.2 App cannot reach the server

Diagnose in this order — the app's error card names the exact host it tried.

```bash
# 1. Is the server up at all?
curl http://127.0.0.1:8000/api/platform/status

# 2. Is it reachable over the LAN (this is what the phone uses)?
curl http://192.168.1.81:8000/api/platform/status

# 3. Can the phone see it?
adb shell ping -c 2 192.168.1.81
```

If (1) works but (2) fails, the server is bound to loopback — restart it with
`--host=0.0.0.0`. If (2) works but (3) fails, the phone is on a different
network or a guest Wi-Fi with client isolation. Behind an ngrok tunnel, check
the public URL instead:

```bash
curl https://<subdomain>.ngrok-free.dev/api/platform/status
```

**Emulator note:** use `http://10.0.2.2:8000` — `localhost` inside an emulator
is the emulator itself.

**Cleartext traffic:** the manifest sets `usesCleartextTraffic="true"` so LAN
HTTP works. Android blocks cleartext to remote hosts on newer target SDKs, which
is why `./build_release.sh` rejects an `http://` URL.

### 7.3 CORS errors in the browser console

Only affects the **web admin console**. The mobile app is not subject to CORS.

Add the origin to `backend/config/cors.php`:

```php
'allowed_origins' => [
    'http://localhost:5173',
    'https://your-app.vercel.app',       // add production domains here
],
```

Private LAN addresses on any port are already permitted by
`allowed_origins_patterns`, so a teammate's phone needs no edit. After changing
config:

```bash
php artisan config:clear
```

A blank admin table with no console error is usually a **missing
`VITE_API_BASE_URL`** rather than CORS — the app falls back to same-origin
`/api/*` and logs a warning at boot.

### 7.4 Database & migration errors

```bash
php artisan migrate:status
php artisan migrate:fresh --seed     # drop everything and rebuild
```

| Error | Fix |
| --- | --- |
| `SQLSTATE[HY000] [1045] Access denied` | Wrong `DB_USERNAME`/`DB_PASSWORD` in `.env` |
| `Base table or view not found` | Run `php artisan migrate` |
| `Unknown database 'community-based-portal'` | `CREATE DATABASE` (§2.3) |
| Migration fails on a re-run | `2026_10_04_000002` uses a `SHOW INDEX` check (MariaDB has no functional unique index); ensure the user has `ALTER` rights |
| Migrations appear to do nothing | `php artisan migrate --force` if `APP_ENV=production` |

### 7.5 Flutter / Android issues

| Symptom | Fix |
| --- | --- |
| `Android SDK version 36` missing in `flutter doctor` | Install via Android Studio SDK Manager, or set `sdk.dir` in `mobile/android/local.properties` |
| `Android license status unknown` | `flutter doctor --android-licenses` and accept |
| `Failed to install APK` | Uninstall first: `adb uninstall ph.cblrep.app` |
| Gradle build fails after a Flutter upgrade | `flutter clean && flutter pub get`, then rebuild |
| `RenderFlex overflowed` yellow/black stripes | Run `flutter test` — layout regressions are covered by `mobile/test/` |
| App opens to a blank/spinner screen | Backend unreachable; the launch gate now shows the host it tried with a Retry button |
| Barters / Barter Requests tabs always empty | Expected: a barter only exists once a member proposes one from a listing (§4.7). Answer a barter listing with "Make a trade offer", or a need with "I have this". |

### 7.5a Running the backend test suite

```bash
cd backend
php artisan migrate      # schema must be current first
php artisan test         # or: composer test / php vendor/bin/phpunit
```

Current result: **137 passed, 467 assertions, 0 skipped** (≈40 s).

**Where the tests run.** `backend/phpunit.xml` points at the development
MariaDB database. Two constraints forced this:

- `pdo_sqlite` is not installed on this machine, so the `phpunit.xml.dist`
  SQLite default cannot connect.
- Migration `2026_10_04_000002` uses MariaDB-only DDL (a `STORED` generated
  column plus a plain unique index — MariaDB has no functional-key index).

**Safety — read before switching test traits.** The tests use
`DatabaseTransactions`, **not** `RefreshDatabase`. Laravel's `migrate:fresh`
(which `RefreshDatabase` triggers) calls `MySqlBuilder::dropAllTables()`, which
lists every table in the schema with **no table-prefix exemption** — pointed at
the development database it would drop the development rows too.
`DatabaseTransactions` wraps each test in a transaction and rolls it back, so
the schema and existing data are untouched. Verify with:

```bash
# before and after a test run, counts must match
mysql -u cblrep -p community-based-portal \
  -e "SELECT (SELECT COUNT(*) FROM users) AS users,
             (SELECT COUNT(*) FROM resources) AS resources;"
```

If you want `RefreshDatabase` semantics, create a dedicated schema first:

```sql
CREATE DATABASE `community-based-portal_test`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON `community-based-portal_test`.* TO 'cblrep'@'localhost';
FLUSH PRIVILEGES;
```

then point `DB_DATABASE` in `backend/phpunit.xml` at it. Tests skip (rather
than fail) when the configured database is unreachable.

**Coverage.** 137 tests across unit + feature suites — moderation and
visibility bypass, barangay / purok / registration validation, conversation
participant isolation, public feed pagination and rate limiting, notification
preferences, unverified posting limits, phase-4 listing features, app-version
release channel, plus configuration smoke tests.

### 7.6 Rate limiting

Auth endpoints are throttled in `backend/app/Providers/AppServiceProvider.php`:

| Limiter | Budget |
| --- | --- |
| `auth-login` | 20/min per IP, **plus** 10/min per email |
| `auth-register` | 10/min per IP |
| `password-email` / `password-reset` | 3/min per email |
| `admin-2fa` | 20/min per IP, plus 10/min per challenge token |
| `admin-export` | 10/min per administrator — analytics CSV/PDF |
| `public-read` | 300/min per IP — the unauthenticated `GET /api/listings` feed |

Hitting these returns HTTP **429**, not 401. During repeated local testing, wait
a minute or temporarily raise the limits. The per-account budget on sign-in is
the one a person feels: it was 5/min, which locked a member out for a minute
after two mistyped passwords, so it is now 10/min — still slow enough for a
credential-stuffing run, loose enough for a human.

### 7.7 Admin login / 2FA

```bash
POST /api/admin-login      → stage 1: credentials, returns a challenge token
POST /api/admin/2fa/verify → stage 2: TOTP code, returns the Sanctum token
```

With `MAIL_MAILER=log`, password-reset codes are readable in
`backend/storage/logs/laravel.log`.

---

## 7.8 Continuous integration and delivery

Every push and pull request is tested by GitHub Actions, and a `v*` tag
publishes a signed APK. The full runbook — the branches, the workflows, the
secrets to add and how to cut a release — is in
**[`docs/CI_CD.md`](docs/CI_CD.md)**.

The short version:

| What | Where | How |
| --- | --- | --- |
| The gate | `.github/workflows/ci.yml` | The same file runs on `main` (all three suites) and on each tier branch (its own suite). |
| The API delivery | `.github/workflows/deploy.yml` | A push to `main` updates the Debian host and smoke-tests the API. |
| The console | Vercel | The Git integration redeploys it on every push to `main`. |
| The APK | `.github/workflows/release.yml` | `git tag v1.5.5 && git push origin v1.5.5` builds both signed variants, publishes them, and points the app's update channel at the new one. |

The secrets the workflows need are listed in `docs/CI_CD.md`; until they are
set, the deploy and release jobs report what is missing and stop, and the CI
gate runs on its own.

---

## 8. Quick Reference

```bash
# ── Backend ──────────────────────────────────────────────
cd backend
php artisan serve --host=127.0.0.1 --port=8000
ngrok http 8000                      # public HTTPS tunnel (§5)

# ── Admin console ────────────────────────────────────────
cd frontend
npm run dev                       # :5173, proxied to the API
npm run check                     # lint + production build

# ── Mobile ──────────────────────────────────────────────
cd mobile
flutter pub get
flutter run -d <device_id> --dart-define=CBLREP_API_URL=https://<subdomain>.ngrok-free.dev
flutter run -d <device_id> --dart-define=CBLREP_API_URL=http://<LAN_IP>:8000   # same Wi-Fi
./build_release.sh https://api.your-domain.com
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Default endpoints

| Service | URL |
| --- | --- |
| Laravel API (local) | `http://127.0.0.1:8000/api` |
| Laravel API (ngrok) | `https://<subdomain>.ngrok-free.dev/api` |
| API health | `…/api/platform/status` |
| Admin dev server | `http://localhost:5173` |
| Seeded admin | `admin@cblrep.ph` / `adminpass123` (+ TOTP from seeder output) |
| Seeded demo members | `maria.santos@cblrep.test` etc. / `Demo@1234` |