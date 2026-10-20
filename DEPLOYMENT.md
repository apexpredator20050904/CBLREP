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

### Moving it to the production API

When `api.cblrep.ph` serves again:

1. drop the `/api/*` rewrite from `frontend/vercel.json`;
2. set `VITE_API_BASE_URL` to `https://api.cblrep.ph` (a project environment
   variable, or the `PRODUCTION_API_URL` variable the release workflow uses);
3. redeploy — the value is inlined into the bundle **at build time**.

The `api.cblrep.ph` origin is already in the API's `allowed_origins`, so no
CORS change is needed for that move.

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

## 2. Environment variable (required)

Set this in **Vercel → Project → Settings → Environment Variables**:

| Name | Example value | Scope |
| --- | --- | --- |
| `VITE_API_BASE_URL` | `https://api.cblrep.ph` | Production (and Preview if you want previews talking to the same API) |

- No trailing slash and **no** `/api` suffix — `src/services/adminApi.js` appends
  `/api` itself.
- `VITE_*` values are inlined into the bundle **at build time**. Changing the
  variable requires a new deployment to take effect.
- `VITE_API_TARGET` is dev-only (the Vite proxy target). Do **not** set it in
  Vercel.

Without `VITE_API_BASE_URL` the app falls back to same-origin `/api/*` and logs
a console warning; pages load but all data requests fail.

> On Vercel the value **must** be absolute. Vercel serves only static files —
> there is no PHP-FPM to route a relative `/api/*` to, so an empty value means
> every request 404s against the Vercel origin.

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