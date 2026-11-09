# Deploying the CBLREP Admin Console to Vercel

This deploys **only the React/Vite admin console** (`frontend/`). The Laravel API
(`backend/`) and the Flutter app (`mobile/`) are deployed separately — see the
"Backend checklist" at the bottom.

---

## 0. Where the console is deployed, and what it talks to

| | |
| --- | --- |
| **Console** | `https://cblrep-frontend.vercel.app` (Vercel project `cblrep-frontend`, team `team-jesus7`) |
| **API it calls** | `https://cblrep-frontend.vercel.app/api/*` — **the same origin**, proxied by Vercel to the tunnel |
| **The tunnel** | `https://contest-bunny-unsorted.ngrok-free.dev` → this machine's Laravel API on port 8000 |
| **Why not `api.cblrep.ph`?** | That host is not serving: it accepts TCP on 80/443 but answers the TLS handshake with an `internal error` alert and returns an empty reply. The console points at the tunnel until the host is back. |

### The API is same-origin, exactly as in production

The console calls **its own origin** (`/api/*`), and `frontend/vercel.json`
rewrites that to the tunnel. This is the same topology the production host
uses: on the Debian server, nginx serves the console's static files and routes
`/api/*` to PHP-FPM. Here, Vercel serves the static files and routes `/api/*`
to the tunnel.

Two consequences worth knowing:

- **There is no CORS at all** — the browser talks to its own origin, so no
  preflight and no `Access-Control-Allow-Origin`. The `*.vercel.app` pattern
  in `backend/config/cors.php` is still there for the day the console is
  pointed straight at the API.
- **The `ngrok-skip-browser-warning` header** (`frontend/src/services/adminApi.js`)
  is what makes the tunnel usable from a browser. ngrok's free tier answers a
  browser GET with its "You are about to visit…" warning page instead of the
  API's JSON, which broke the session check and every listing read. The header
  tells ngrok to pass the request through; a normal API ignores it.

**The console only works while this machine and the ngrok tunnel are running.**
The laptop going to sleep takes the console's data down with it. That is the
price of deploying before the production host is repaired.

Run `./scripts/check-connections.sh` from the repository root to verify the
whole chain — MariaDB, the local API, the tunnel, `APP_URL` vs the rewrite
host, and the console's own `/api` — before blaming the console.

### Moving it to the production API

When `api.cblrep.ph` serves again:

1. drop the `/api/*` rewrite from `frontend/vercel.json`;
2. set `VITE_API_BASE_URL` to `https://api.cblrep.ph` (a project environment
   variable, or the `PRODUCTION_API_URL` variable the release workflow uses);
3. redeploy — the value is inlined into the bundle **at build time**.

The `api.cblrep.ph` origin is already in the API's `allowed_origins`, so no
CORS change is needed for that move.

### The two Vercel projects

| Project | Serves | Deploys from |
| --- | --- | --- |
| `cblrep-frontend` | **The console.** `https://cblrep-frontend.vercel.app` | `main`, and any pull request |
| `cblrep` | A second copy of the same console. Harmless, but it doubles the deploys and adds a second red check on every pull request — worth deleting if you are not using it. | `main` only |

The tier branches (`back-end`, `front-end`, `flutter-app`) are **skipped** on
purpose: they hold one tier at their root, so the console's `frontend/`
directory is not there to build. Each project carries an *ignored build
step* that skips those branches rather than failing them.

To see or change those rules: **Vercel → the project → Settings → Git →
Ignored Build Step**.

---

## 1. Configuration (already in the repo)

| File | Purpose |
| --- | --- |
| `frontend/vercel.json` | The console's Vercel config: the SPA rewrite, the `/api/*` proxy to the tunnel, and the cache headers. **It lives in `frontend/`, not at the repository root** — Vercel reads the config from the *project's root directory*, and the project's root directory is `frontend`. |
| `.vercelignore` (root) | Keeps `backend/`, `mobile/`, `storage/`, logs and `node_modules` out of the Vercel upload |
| `frontend/.env.example` | Documents every environment variable for the Vercel dashboard |

> The repository root used to carry a `vercel.json` with `"rootDirectory":
> "frontend"`. **`rootDirectory` is not a `vercel.json` property** — it is a
> project setting — so Vercel rejected the file outright
> (`Invalid vercel.json - should NOT have additional property
> 'rootDirectory'`) and every deployment failed before the build started. The
> root file is gone and the config lives where Vercel actually reads it.

**SPA routing:** `vercel.json` rewrites everything except `/api/*` to
`/index.html`, so refreshing `/login`, `/admin/listings`, `/admin/settings`, etc.
loads the app instead of returning 404. Vercel checks the filesystem *before*
applying rewrites, so hashed assets under `/assets/` still resolve normally.

---

## 2. Environment variable (pick the wiring first)

There are two supported wirings. **Do not mix them.**

| | **A · Same-origin rewrite (current)** | **B · Direct to the API** |
| --- | --- | --- |
| `frontend/vercel.json` | keeps the `/api/:path*` rewrite | rewrite removed |
| `VITE_API_BASE_URL` | **empty** | the API origin, e.g. `https://api.cblrep.ph` |
| Browser calls | the console's own origin, proxied by Vercel | the API origin directly |
| CORS | not involved | `backend/config/cors.php` must allow the console origin |
| Use when | the API is behind the ngrok tunnel | `api.cblrep.ph` (or another host) serves the API |

Set the variable in **Vercel → Project → Settings → Environment Variables**
(or leave it unset for wiring A — unset and empty behave the same):

| Name | Value for A | Value for B |
| --- | --- | --- |
| `VITE_API_BASE_URL` | *(empty / unset)* | `https://api.cblrep.ph` |

- No trailing slash and **no** `/api` suffix in B — `src/services/adminApi.js`
  appends `/api` itself.
- `VITE_*` values are inlined into the bundle **at build time**. Changing the
  variable requires a new deployment to take effect.
- `VITE_API_TARGET` is dev-only (the Vite proxy target). Do **not** set it in
  Vercel.
- In wiring A the rewrite host is hardcoded (Vercel rewrites cannot read env
  vars), so it must match `backend/.env`'s `APP_URL`. Edit `frontend/vercel.json`
  and redeploy whenever the tunnel host changes.

`./scripts/check-connections.sh` reports which wiring is in place, and fails if
`vercel.json`'s rewrite host and `APP_URL` disagree.

> An **absolute** base URL with the rewrite still in place is not fatal but is
> redundant: the browser then calls the tunnel cross-origin and needs CORS
> while Vercel's rewrite sits unused. Pick one.

---

## 3. Option A — Git integration (recommended)

1. Push this repository to GitHub/GitLab/Bitbucket.
2. In Vercel: **Add New → Project → Import** the repo.
3. Vercel reads `vercel.json`; confirm the dashboard shows:
   - Framework Preset: **Vite**
   - Root Directory: `frontend`
   - Build Command: `npm run build`
   - Output Directory: `dist`
4. Add `VITE_API_BASE_URL` under **Settings → Environment Variables** for
   Production (and Preview if needed).
5. **Deploy**. Every push to the default branch redeploys automatically.

> If you previously set a Root Directory in the dashboard, keep it `frontend` —
> it matches `vercel.json`. If you instead set the dashboard Root Directory to
> `.` (repo root), clear `rootDirectory` in `vercel.json`; do not set it both ways.

---

## 4. Option B — Vercel CLI

```bash
cd frontend

# First-time link (creates/links the project and stores .vercel/)
npx --yes vercel@latest link

# Preview deployment (safe, temporary URL)
npm run deploy:preview

# Production deployment
VITE_API_BASE_URL=https://api.your-domain.com npm run deploy
```

To set the variable once so every later deploy picks it up:

```bash
cd frontend
echo -n "https://api.your-domain.com" | npx --yes vercel@latest env add VITE_API_BASE_URL production
```

Tip: `npm run deploy` shells out to the Vercel CLI, so `--prod` works when
forwarded through npm.

### 4.1 The projects on this repository

The repository is connected to a Vercel team (`team-jesus7`) with **two**
projects, both deployed by the Git integration on every push:

| Project | Serves | State |
| --- | --- | --- |
| `cblrep-frontend` | The admin console | The deployment to fix — see below. |
| `cblrep` | The repository root | The root is the monorepo (`backend/`, `frontend/`, `mobile/`) and holds no app of its own, so this project has nothing to build. It can be left alone or removed from the team. |

**`cblrep-frontend` needs three settings**, and the first two are what make
its deployment fail:

| Setting | Value | Why |
| --- | --- | --- |
| **Root Directory** | `frontend` | The console is `frontend/`. A root directory left over from when the repository root *was* the Vite app points at `frontend/frontend/`, and the build fails. |
| **Build Command** | `npm run build` | The default for the Vite preset. |
| **Output Directory** | `dist` | The default for the Vite preset. |
| **Env var** | `VITE_API_BASE_URL` = the API origin | Inlined at build time; see §2. |

The repository's own `vercel.json` already declares `rootDirectory: frontend`,
the SPA rewrite and the cache headers, so the project only has to point at
the right directory.

**Reading a failed deployment's logs** needs a Vercel token:

```bash
npx vercel inspect <deployment-id> --logs --token $VERCEL_TOKEN
```

The failure message on the pull request names the deployment id.

---

## 5. Pre-deploy verification

```bash
cd frontend
npm ci            # exactly what Vercel runs
npm run check     # lint + production build; must be clean
npm run start     # serve ./dist locally, then hard-refresh /admin/listings
```

`npm run check` must report **0 problems** from ESLint and a successful
`✓ built in …`.

---

## 6. Backend checklist (Laravel API)

The console is useless without a reachable API. On the API host:

- The seeded login `admin@cblrep.ph` / `adminpass123` is **local demo only —
  change before any real deployment**. Set `ADMIN_SEED_EMAIL` and
  `ADMIN_SEED_PASSWORD` in the server environment; prefer `php artisan
  admin:create` for a live server because `db:seed` truncates every table.
- `APP_URL=https://api.your-domain.com`, `APP_ENV=production`, `APP_DEBUG=false`
- `php artisan config:cache && php artisan route:cache`
- **CORS** — add the Vercel domain(s) to `backend/config/cors.php`:
  ```php
  'allowed_origins' => [
      'https://cblrep-admin.vercel.app',
      'https://your-custom-domain.com',
  ],
  ```
- Serve over HTTPS; Sanctum bearer tokens travel in the `Authorization` header
  so a secure-site API is fine.
- Health check after deploy: `curl https://api.your-domain.com/api/platform/status`

---

## 7. Post-deploy smoke test

1. Open the Vercel URL → you land on `/login`.
2. Sign in with an admin account (2FA challenge included).
3. Hard-refresh on `/admin/listings` and `/admin/settings` — must not 404.
4. Confirm lists load (proves CORS + `VITE_API_BASE_URL` are correct).
5. Check browser console for the CBLREP `VITE_API_BASE_URL` warning (should be absent).