# Deploying the CBLREP Admin Console to Vercel

This deploys **only the React/Vite admin console** (`frontend/`). The Laravel API
(`backend/`) and the Flutter app (`mobile/`) are deployed separately — see the
"Backend checklist" at the bottom.

---

## 0. Where the console is deployed, and what it talks to

| | |
| --- | --- |
| **Console** | `https://cblrep-admin.vercel.app` (Vercel project `cblrep-admin`) |
| **API it calls** | `https://contest-bunny-unsorted.ngrok-free.dev` — the reserved ngrok subdomain, for now |
| **Why not `api.cblrep.ph`?** | That host is not serving: it accepts TCP on 80/443 but answers the TLS handshake with an `internal error` alert and returns an empty reply. The console points at the tunnel until the host is back. |

**The console only works while this machine and the ngrok tunnel are running.**
The tunnel is the API the deployment calls, so the laptop going to sleep takes
the console down with it. That is the price of deploying before the production
host is repaired.

**To move it to the production API** (once `api.cblrep.ph` serves again):

1. change the repository variable `VERCEL_API_BASE_URL` to `https://api.cblrep.ph`;
2. push anything to `main` (or run the *Deploy console* workflow by hand).

The value is inlined into the bundle **at build time**, so a redeploy is what
makes it take effect. The `api.cblrep.ph` origin is already in the API's
`allowed_origins`, so no CORS change is needed for that move.

**CORS, once and for all:** Vercel cannot run PHP-FPM, so a console served
from there calls the API cross-origin and the API must answer the preflight.
`backend/config/cors.php` carries a `*.vercel.app` pattern for exactly that —
it covers the production alias and every random preview deployment URL. A
foreign origin still gets no `Access-Control-Allow-Origin`.

---

## 1. Configuration (already in the repo)

| File | Purpose |
| --- | --- |
| `vercel.json` (root) | Vercel project config: `rootDirectory: frontend`, `outputDirectory: dist`, SPA rewrites, cache headers |
| `.vercelignore` (root) | Keeps `backend/`, `mobile/`, `storage/`, logs and `node_modules` out of the Vercel upload |
| `frontend/.env.example` | Documents every environment variable for the Vercel dashboard |

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

### 4.1 Option C — deployed by CI (what this repository uses)

`.github/workflows/vercel.yml` deploys the console on every push to `main`.
It links the project, writes `VITE_API_BASE_URL` as a **production
environment variable** (so the value is inlined at build time), and deploys.

| Where | Name | Kind |
| --- | --- | --- |
| Repository secret | `VERCEL_TOKEN` | A Vercel token (vercel.com → Account Settings → Tokens). |
| Repository variable | `VERCEL_PROJECT` | `cblrep-admin` |
| Repository variable | `VERCEL_API_BASE_URL` | The API the console calls. **Change this to move the console to another API**, then push. |
| Repository variable | `VERCEL_ORG` | Only for a team account; a personal token needs no scope. |

Until the token is set, the workflow reports that Vercel is not wired and
stops — it does not fail every push. Once it is set, a broken deployment
fails loudly.

The project's own settings carry the root directory (`frontend`) and the SPA
rewrite, so the console's `/admin/*` routes survive a hard refresh.

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