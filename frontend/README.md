# CBLREP — Admin console (React + Vite)

The municipal console for Trinidad, Bohol: verify residents, moderate
Offers & Needs, follow the barter ledger, handle reports and export the
analytics.

| | |
| --- | --- |
| **Branch** | `front-end` — the source of truth for `frontend/` in the monorepo |
| **Stack** | React 19 · Vite 8 · Tailwind 4 · Leaflet |
| **Deployed at** | **https://cblrep-frontend.vercel.app** (Vercel redeploys it on every push to `main`) |
| **Docs** | [DEPLOYMENT.md](https://github.com/apexpredator20050904/CBLREP/blob/main/DEPLOYMENT.md) · [RUNNING.md](https://github.com/apexpredator20050904/CBLREP/blob/main/RUNNING.md) |

## Run it

```bash
npm install
npm run dev        # Vite dev server on :5173, proxies /api/* to the API
npm run check      # lint + production build — the same gate CI and Vercel run
```

`VITE_API_BASE_URL` stays **empty** for local development: requests are
relative `/api/*` and the Vite proxy forwards them to the API. On Vercel it
is the console's own origin, because `/api/*` is proxied to the API by a
rewrite — see [DEPLOYMENT.md](https://github.com/apexpredator20050904/CBLREP/blob/main/DEPLOYMENT.md).

## Sign in

`admin@cblrep.ph` / `adminpass123`, then the TOTP code from your
authenticator app. The console's data comes from the API, so the API and its
tunnel have to be running.
