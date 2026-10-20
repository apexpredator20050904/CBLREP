# Deploying the CBLREP Admin Console to Vercel

This deploys **only the React/Vite admin console** (`frontend/`). The Laravel API
(`backend/`) and the Flutter app (`mobile/`) are deployed separately — see the
"Backend checklist" at the bottom.

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
| `VITE_API_BASE_URL` | `https://api.your-domain.com` | Production (and Preview if you want previews talking to the same API) |

- No trailing slash and **no** `/api` suffix — `src/services/adminApi.js` appends
  `/api` itself.
- `VITE_*` values are inlined into the bundle **at build time**. Changing the
  variable requires a new deployment to take effect.
- `VITE_API_TARGET` is dev-only (the Vite proxy target). Do **not** set it in
  Vercel.

Without `VITE_API_BASE_URL` the app falls back to same-origin `/api/*` and logs
a console warning; pages load but all data requests fail.

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