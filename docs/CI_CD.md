# CI/CD

How the three tiers of CBLREP are tested on every push and delivered to
production. Written for the maintainer of the repository; for how to *run*
the project locally, see [`RUNNING.md`](../RUNNING.md).

## The shape of the repository

The GitHub repository is a **monorepo**, and each tier also has its own
branch, where that tier's files sit at the **root**:

| Branch | Layout | What it is |
| --- | --- | --- |
| `main` | `backend/`, `frontend/`, `mobile/` | The integration branch. Everything below is merged here. |
| `back-end` | `artisan`, `app/`, `tests/` at the root | The Laravel API — the source of truth for `backend/`. |
| `front-end` | `package.json`, `src/` at the root | The React admin console — the source of truth for `frontend/`. |
| `flutter-app` | `pubspec.yaml`, `lib/` at the root | The Flutter app — the source of truth for `mobile/`. |

The tiers are synced into `main` with **subtree merges**, so the history of
a tier branch is visible in `main`:

```bash
git checkout main
git subtree pull --prefix=backend origin back-end
git commit --amend -m "monorepo: update backend/ (subtree merge: …)"
git push
```

Work happens on a tier branch, is subtree-merged into `main` (or into
`integration`, which is then merged by pull request), and the pull request
is what the CI gate protects.

## The workflows

| Workflow | File | Runs on | Does |
| --- | --- | --- | --- |
| **CI** | `.github/workflows/ci.yml` | every push and pull request on `main` and the three tier branches | The gate: the three test suites. |
| **Deploy API** | `.github/workflows/deploy.yml` | push to `main` (or manually) | Delivers the Laravel API to the Debian host. |
| **Release** | `.github/workflows/release.yml` | a `v*` tag | Builds the signed APKs, publishes them, points the app's update channel at them. |
| **Dependabot** | `.github/dependabot.yml` | weekly | Opens dependency update pull requests for all three tiers. |

### CI — one file, two layouts

`ci.yml` lives at the root of **four** branches. It detects at runtime which
layout it is looking at and runs only the jobs that apply:

```
backend/artisan exists  → monorepo: backend/ + frontend/ + mobile/
artisan exists          → the backend tier
package.json exists     → the frontend tier
pubspec.yaml exists     → the mobile tier
```

| Job | What it runs | Needs |
| --- | --- | --- |
| `Backend · PHP tests` | `composer install` → `artisan migrate` → a schema precheck → `php artisan test` | A **MariaDB 10.11 service container** |
| `Frontend · lint + build` | `npm ci` → `npm run check` (ESLint + the production bundle) | Node 20 |
| `Mobile · analyze + test` | `flutter pub get` → `flutter analyze` → `flutter test` | The Flutter SDK |

Three things this file exists to get right:

1. **The backend suite skips rather than fails when the database is
   unreachable** — a skipped suite is green. The job therefore checks the
   schema is reachable *before* the suite runs, so a broken connection fails
   the build instead of passing it silently.
2. **`flutter analyze` exits non-zero on the project's pre-existing infos.**
   It is gated with `--no-fatal-warnings --no-fatal-infos`, so only real
   errors block a push. The infos are debt, not gate failures.
3. **A fresh checkout has no `bootstrap/cache`, no `storage/` and no `.env`.**
   The backend job creates them, and writes a minimal `.env` — Laravel reads
   the environment file on every boot, and the read raises a warning that
   PHPUnit would otherwise report on every single test.

`phpunit.xml` fails on warnings, notices and risky tests, so a green build
means the assertions really ran.

### Deploy API — the Debian host

The console is deployed by **Vercel through the Git integration** (every push
to `main` redeploys it), so this workflow only delivers the **API**. The host
already holds a git checkout of the monorepo at `/var/www/cblrep`, so the
workflow drives that checkout rather than shipping files — the same sequence
as [`backend/deploy/DEPLOY_DEBIAN.md`](../backend/deploy/DEPLOY_DEBIAN.md) §12:

```
git fetch origin && git checkout main && git pull --ff-only
cd backend && composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache && php artisan view:cache
cd ../frontend && npm ci && npm run build
sudo systemctl reload php8.3-fpm nginx
```

It finishes with a smoke test against `https://api.cblrep.ph/api/platform/status`,
retrying five times while PHP-FPM comes back up.

The deploy user needs passwordless sudo for `systemctl reload php8.3-fpm`,
`systemctl reload nginx` and `systemctl restart cblrep-queue`.

### Release — a signed APK

Push a `v*` tag and the workflow:

1. **checks the tag against the app version** — `v1.5.5` must equal the
   `version:` line in `mobile/pubspec.yaml`, and the build number in that
   line is the `versionCode` the server publishes. A mis-tagged release
   fails the job instead of publishing an APK the update channel cannot
   describe;
2. restores the **release keystore** from the secrets (it never enters the
   repository);
3. builds **two** APKs — `app-release.apk` against the production API and
   `app-release-ngrok.apk` against the ngrok tunnel, the two-asset
   convention of the v1.5.x releases;
4. publishes them to the GitHub Release and records their SHA256;
5. **points the deployed server's release channel at the new asset** —
   `APP_VERSION_CODE`, `APP_VERSION_NAME`, `APP_APK_URL` and
   `APP_APK_SHA256` — so a phone on an older build sees the update prompt
   and downloads the new one. Publishing the APK is only half of a release.

```bash
# from a clean checkout of main
git tag v1.5.5 && git push origin v1.5.5
```

## Settings → Secrets and variables → Actions

### Secrets

| Name | Used by | What it is |
| --- | --- | --- |
| `DEPLOY_HOST` | deploy, release | The Debian host's address. |
| `DEPLOY_USER` | deploy, release | The deploy user (needs passwordless sudo for the units above). |
| `DEPLOY_SSH_KEY` | deploy, release | That user's private key. |
| `ANDROID_KEYSTORE_BASE64` | release | `base64 -w0 mobile/android/cblrep-release.jks`. |
| `ANDROID_KEYSTORE_PASSWORD` | release | From `mobile/android/key.properties`. |
| `ANDROID_KEY_ALIAS` | release | From `mobile/android/key.properties`. |
| `ANDROID_KEY_PASSWORD` | release | From `mobile/android/key.properties`. |
| `VERCEL_TOKEN` | — | Only if the console is ever deployed by the CLI instead of the Git integration. |

### Variables

| Name | Used by | What it is |
| --- | --- | --- |
| `PRODUCTION_API_URL` | release | `https://api.cblrep.ph` — baked into the production APK. |
| `NGROK_API_URL` | release | `https://<subdomain>.ngrok-free.dev` — baked into the ngrok APK. |

The keystore and its passwords are the app's signing identity: losing them
means a new signing key, and Android refuses to update an app signed with a
different one. Keep a copy of `mobile/android/cblrep-release.jks` somewhere
safe — the same way the server's `APP_KEY` has to be kept (without it the
enrolled admins lose their 2FA).

## Notes

- The tier branches carry their own copy of `ci.yml`. When a tier is
  subtree-merged into `main`, that copy lands in `main:backend/.github/…`.
  GitHub only reads workflows from the repository root, so those copies are
  inert — the root copy is the one that runs.
- Keep the four copies of `ci.yml` identical. The monorepo copy is the one
  that runs the most (it runs all three jobs), so start from it.
- The release channel on the server is what the app polls on launch
  (`GET /api/app-version`). A published release that the server does not
  describe is invisible to the phones that need it.
