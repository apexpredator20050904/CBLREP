# CBLREP — Community-Based Learning & Resource Exchange Portal

The capstone: a **Laravel API**, a **React admin console** and a **Flutter
app** for a barangay-level resource exchange in Trinidad, Bohol. Members post
what they have and what they need; neighbours trade, give and buy; the
municipal console verifies residents and moderates the board.

| Tier | Path | Stack | Where it runs |
| --- | --- | --- | --- |
| Admin console | `frontend/` | React 19 · Vite 8 · Tailwind 4 | **`https://cblrep-frontend.vercel.app`** |
| API | `backend/` | Laravel 12 · PHP 8.3 · MariaDB | `http://127.0.0.1:8000/api` (behind ngrok) |
| Mobile app | `mobile/` | Flutter · Dart 3.12 | the member's phone |

## Branches

| Branch | Holds | Used for |
| --- | --- | --- |
| `main` | the monorepo: `backend/`, `frontend/`, `mobile/` | integration, deployment, the releases |
| `back-end` | the Laravel tier at the branch root | daily work on the API |
| `front-end` | the React tier at the branch root | daily work on the console |
| `flutter-app` | the Flutter tier at the branch root | daily work on the app |
| `integration`, `mobile` | legacy leftovers | — |

Each tier branch is the **source of truth** for its tier; `main` is kept in
step with subtree merges, so a tier's history is visible in the monorepo:

```bash
git checkout main
git subtree pull --prefix=backend origin back-end
git commit --amend -m "monorepo: update backend/ (subtree merge: …)"
```

A **local workspace** can be a single clone of `main`, or three clones (one
per tier branch) side by side — each folder with its own `.git`, so you can
pull, commit and push one tier without touching the others.

Every push to `main` is tested by GitHub Actions and redeploys the console.

## Quick start

### 1. The API

```bash
cd backend
composer install
cp .env.example .env && php artisan key:generate

# the database and its user have to exist before it can be migrated into
mysql -u root -p
#   CREATE DATABASE community-based-portal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
#   CREATE USER 'cblrep'@'localhost' IDENTIFIED BY 'your_password';
#   GRANT ALL PRIVILEGES ON community-based-portal.* TO 'cblrep'@'localhost';
#   FLUSH PRIVILEGES;   (then put the same password in .env's DB_PASSWORD)

php artisan migrate --force
php artisan db:seed --force          # creates the administrator (destructive)
php artisan db:seed --class=DemoSeeder   # optional demo listings, additive

php artisan serve --host=127.0.0.1 --port=8000
```

`db:seed` creates the administrator — `admin@cblrep.ph` / `adminpass123` —
enrols TOTP 2FA and prints the secret. `DemoSeeder` adds the demo listings
and members on top, and never deletes anything.

### 2. The tunnel

The phone app and the deployed console both reach this machine through it:

```bash
cd backend
ngrok http 8000
```

### 3. The admin console

Open **`https://cblrep-frontend.vercel.app`** and sign in with the seeded
administrator. It reads its data through the tunnel, so steps 1 and 2 have to
be running.

To work on the console itself:

```bash
cd frontend
npm install
npm run dev        # Vite dev server on :5173, proxies /api/* to the API
npm run check      # lint + production build — the same gate CI runs
```

### 4. The mobile app

```bash
cd mobile
flutter pub get
flutter run -d <device_id> --dart-define=CBLREP_API_URL=https://<subdomain>.ngrok-free.dev
```

The API host is **compiled into the binary**, so it is baked in at build
time — see `mobile/BUILD.md`. A distributable APK:

```bash
cd mobile
./build_release.sh https://api.cblrep.ph     # or your ngrok subdomain
```

## Documentation

| File | Contents |
| --- | --- |
| [`RUNNING.md`](RUNNING.md) | The full local runbook: setup, the deployed console, test accounts, tunnelling, troubleshooting, CI |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Deploying the admin console to Vercel, and moving it to the production API |
| [`docs/CI_CD.md`](docs/CI_CD.md) | The CI/CD runbook: the gate, the workflows, the secrets, cutting a release |
| [`backend/deploy/DEPLOY_DEBIAN.md`](backend/deploy/DEPLOY_DEBIAN.md) | Deploying the API to a Linux server (nginx + PHP-FPM + MariaDB) |
| [`mobile/BUILD.md`](mobile/BUILD.md) | Release-APK signing and the compiled-in API URL |
| [`docs/REFACTOR_BARTER_ONLY.md`](docs/REFACTOR_BARTER_ONLY.md) | Why the portal is direct bartering only |

## CI and releases

- **The gate** — `.github/workflows/ci.yml` runs the backend suite (against a
  real MariaDB), the console's lint and build, and the app's analyzer and
  widget tests, on every push and pull request.
- **The APK** — `git tag v1.5.5 && git push origin v1.5.5` builds both
  signed variants, publishes them to the GitHub Release, and points the
  app's update channel at the new one.
- **The console** — the Vercel Git integration redeploys it on every push to
  `main`.

## Backups

`scripts/make_defense_backup.sh` produces the shareable and private archives in
`storage/backups/` (database dump, release APK, project tarballs, checksums).
The `-SECRETS` archive and the keystore are **never** committed or shared —
`storage/` is git-ignored.

## Repository hygiene

Secrets (`.env`, the signing keystore, `key.properties`), uploaded user
content (`backend/storage/app/public/*`), compiled bundles (`frontend/dist`,
`backend/public/build`), dependency folders and the local runtime logs are
git-ignored and must not be re-committed.
