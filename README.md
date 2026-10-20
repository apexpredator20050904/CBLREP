# CBLREP — Unified Project Workspace

One directory that brings together all three parts of the **CBLREP**
(Community-Based Learning & Resource Exchange Portal) capstone. Each part is a
full, independent clone of the shared repository
[`apexpredator20050904/CBLREP`](https://github.com/apexpredator20050904/CBLREP),
checked out from its own branch.

## Structure

| Folder      | Branch         | Stack                              |
| ----------- | -------------- | ---------------------------------- |
| `frontend/` | `front-end`    | React 19 + Vite 8 admin console    |
| `backend/`  | `back-end`     | Laravel 12 API (PHP 8.2+, MySQL)   |
| `mobile/`   | `flutter-app`  | Flutter app (Android + iOS)        |

Each folder has its own `.git`, so you can pull, commit, and push each part
separately on its branch. The three are also merged into an `integration`
monorepo branch (`backend/`, `frontend/`, `mobile/`).

## Quick start

### Backend (`backend/`, branch `back-end`)

```bash
cd backend
composer install
cp .env.example .env && php artisan key:generate
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8000
```

### Frontend (`frontend/`, branch `front-end`)

```bash
cd frontend
npm install
npm run dev        # Vite dev server on :5173, proxies /api/* to the backend
npm run build      # production bundle in dist/
```

### Mobile (`mobile/`, branch `flutter-app`)

```bash
cd mobile
flutter pub get
flutter run        # debug, against a backend on your LAN
```

The API host is compiled into the app at build time — see `mobile/BUILD.md`.
Build a distributable APK with:

```bash
cd mobile
./build_release.sh https://api.your-domain.com
```

## Documentation

| File | Contents |
| ---- | -------- |
| `RUNNING.md` | Full local runbook: setup, test accounts, testing, tunnelling, backups |
| `DEPLOYMENT.md` | Deploying the admin console to Vercel |
| `mobile/BUILD.md` | Release-APK signing and the compiled-in API URL |

Deploying the API to a Linux server (nginx + PHP-FPM) is covered in
`RUNNING.md`; the production checklist lives in the deployment review.

## Backups

`scripts/make_defense_backup.sh` produces the shareable and private archives in
`storage/backups/` (database dump, release APK, project tarballs, checksums).
The `-SECRETS` archive and the keystore are **never** committed or shared.

## Repository hygiene

Secrets (`.env`, signing keystore, `key.properties`), uploaded user content
(`backend/storage/app/public/*`), compiled bundles (`public/admin`, `public/build`,
`frontend/dist`) and the local SQLite file are git-ignored and must not be
re-committed.
