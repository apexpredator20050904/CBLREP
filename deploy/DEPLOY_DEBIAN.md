# Deploying CBLREP to a Debian server (nginx + PHP-FPM + MariaDB)

This deploys the **whole stack** to one Debian host, `api.cblrep.ph`:

| Piece | Where it runs | Public URL |
| --- | --- | --- |
| Laravel JSON API | PHP-FPM behind nginx | `https://api.cblrep.ph/api/*` |
| React admin console | static `frontend/dist` via nginx | `https://api.cblrep.ph/login`, `/admin/*` |
| Flutter mobile app | the member's phone (APK) | talks to `https://api.cblrep.ph` |

**Security posture:** the API is the only thing exposed to the internet. MySQL
and phpMyAdmin listen on `127.0.0.1` only and are never opened in the firewall —
reach them through an SSH tunnel if you must (step 9).

Placeholders used below: `api.cblrep.ph`, `/var/www/cblrep`, PHP **8.3**, socket
`/run/php/php8.3-fpm.sock`. Adjust if your versions differ.

---

## 0. What you need first

- A Debian 12/13 server with root or `sudo`.
- A DNS **A** record: `api.cblrep.ph` -> the server's public IPv4.
  (Wait for it to resolve before running certbot.)
- The repository on GitHub: `https://github.com/apexpredator20050904/CBLREP`.
  The deployable branches are `back-end`, `front-end`, `flutter-app`; the
  `integration` branch / PR #1 contains the same code under `backend/`,
  `frontend/`, `mobile/` in one tree.

---

## 1. Packages

```bash
sudo apt update
sudo apt install -y nginx mariadb-server git unzip curl \
  php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml \
  php8.3-curl php8.3-zip php8.3-gd php8.3-bcmath php8.3-intl \
  certbot python3-certbot-nginx

# Composer (for backend dependency install on the server)
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
```

Verify PHP-FPM is up and note the socket path:

```bash
systemctl status php8.3-fpm --no-pager
ls /run/php/            # expect: php8.3-fpm.sock
php -v
```

> **Never expose phpMyAdmin or MySQL.** No `apt install phpmyadmin` needed; if it
> is already present it binds to localhost and stays that way (step 9).

---

## 2. Application layout

```bash
sudo mkdir -p /var/www/cblrep
sudo chown -R "$USER":"$USER" /var/www/cblrep

cd /var/www/cblrep
git clone --branch integration https://github.com/apexpredator20050904/CBLREP.git .

# The three subtrees (backend/, frontend/, mobile/) are now present.
ls   # backend  frontend  mobile  README.md  deploy? ...
```

If the repo root does not carry the deploy files, they live in
`backend/deploy/` (nginx config, this document, env template) and
`frontend/.env.production.example`.

---

## 3. Database

```bash
sudo mariadb
```

```sql
-- The name contains a hyphen: back-tick it everywhere.
CREATE DATABASE `community-based-portal`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'cblrep'@'localhost' IDENTIFIED BY 'PUT-A-STRONG-PASSWORD';
GRANT ALL PRIVILEGES ON `community-based-portal`.* TO 'cblrep'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Bind MySQL to loopback only (default) — confirm and harden:

```bash
sudo grep -R "^bind-address" /etc/mysql/ 2>/dev/null || echo "bind-address=127.0.0.1"
# If missing, add `bind-address = 127.0.0.1` under [mysqld] and:
sudo systemctl restart mariadb
```

---

## 4. Backend (Laravel API)

```bash
cd /var/www/cblrep/backend

# Production .env from the template.
cp deploy/env.production.example .env
nano .env      # set DB_PASSWORD (and APP_URL if the domain differs)

composer install --no-dev --optimize-autoloader

# APP_KEY:
#   • fresh database  -> generate a NEW key
php artisan key:generate
#   • restoring an existing DB -> DO NOT run key:generate; copy the original
#     APP_KEY instead, or enrolled admins lose 2FA (see the env template).

php artisan migrate --force

# Public disk for listing photos / verification docs.
php artisan storage:link

# Create the first admin (do NOT run DatabaseSeeder in production — it is
# destructive). Prompts for email/password and offers 2FA enrolment:
php artisan admin:create --email=admin@cblrep.ph --name="System Administrator" --2fa

# Production caches (rebuild these after every deploy that changes code/env).
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

Permissions — PHP-FPM runs as `www-data` and must write to `storage/` and
`bootstrap/cache/`:

```bash
cd /var/www/cblrep
sudo chown -R www-data:www-data backend/storage backend/bootstrap/cache
sudo find backend/storage -type d -exec chmod 775 {} \;
sudo find backend/storage -type f -exec chmod 664 {} \;
```

---

## 5. Frontend (React admin console)

Same host as the API, so the console calls `/api/*` same-origin — leave
`VITE_API_BASE_URL` empty.

```bash
cd /var/www/cblrep/frontend
cp .env.production.example .env.production   # VITE_API_BASE_URL= (empty)

npm ci
npm run build            # outputs frontend/dist
```

(If you prefer an absolute origin, set `VITE_API_BASE_URL=https://api.cblrep.ph`
and rebuild — but empty is correct for the same-host layout.)

---

## 6. nginx

```bash
sudo cp /var/www/cblrep/backend/deploy/nginx/api.cblrep.ph.conf \
        /etc/nginx/sites-available/api.cblrep.ph.conf
sudo ln -sf /etc/nginx/sites-available/api.cblrep.ph.conf \
            /etc/nginx/sites-enabled/api.cblrep.ph.conf
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t && sudo systemctl reload nginx
```

At this point HTTP should already serve the admin console and redirect `/api`.
The HTTPS block in the config references Let's Encrypt paths that do not exist
yet, so create them next before relying on the `443` server.

---

## 7. HTTPS (Let's Encrypt / certbot)

```bash
sudo mkdir -p /var/www/certbot

# Issue certs and let certbot wire the TLS directives into the server block.
sudo certbot --nginx -d api.cblrep.ph

sudo nginx -t && sudo systemctl reload nginx
sudo systemctl enable certbot.timer        # auto-renew
sudo certbot renew --dry-run               # prove renewal works
```

> If `nginx -t` failed before certbot because the `ssl_certificate` paths were
> missing, run certbot with the HTTP-only block first (comment out the `443`
> server), then re-enable it — or simply run `certbot --nginx` which rewrites the
> block for you.

---

## 8. Verify the deployment

```bash
# API health (public):
curl -s https://api.cblrep.ph/api/platform/status | head

# SPA is served (returns the React index, HTTP 200):
curl -sI https://api.cblrep.ph/login | head -1
curl -sI https://api.cblrep.ph/admin/listings | head -1     # hard-refresh must not 404

# TLS:
curl -sI https://api.cblrep.ph | head -1
```

Then in a browser:

1. Open `https://api.cblrep.ph/login` and sign in as the admin you created
   (2FA challenge included). The console should load data — that proves nginx,
   PHP-FPM, the DB and `/api` are all wired correctly.
2. Hard-refresh `/admin/listings` and `/admin/settings` — must not 404.

---

## 9. Lock the server down

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'     # 80 + 443
sudo ufw enable
sudo ufw status
```

- **Do not** `ufw allow 3306` (MySQL) or expose phpMyAdmin. If you need one:

  ```bash
  ssh -L 8080:127.0.0.1:80 you@api.cblrep.ph   # then browse http://localhost:8080/phpmyadmin
  ```

- `.env` and `.git` are already denied by the nginx config.
- `APP_DEBUG=false` keeps stack traces out of API responses.

---

## 10. Background work

The app currently has **no scheduled tasks and no queued jobs** — `routes/console.php`
defines no schedule and nothing dispatches to the queue. `QUEUE_CONNECTION=database`
is set for future use; if you later add jobs, run a worker under systemd/supervisor:

```ini
# /etc/systemd/system/cblrep-queue.service
[Unit]
Description=CBLREP queue worker
After=network.target mariadb.service

[Service]
User=www-data
Restart=always
WorkingDirectory=/var/www/cblrep/backend
ExecStart=/usr/bin/php /var/www/cblrep/backend/artisan queue:work --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
```

(Create the file, then `sudo systemctl daemon-reload && sudo systemctl enable --now cblrep-queue`.)

---

## 11. Mobile app release (APK)

The API origin is **compiled into the APK**, so it must be built with the
production URL:

```bash
cd /var/www/cblrep/mobile         # or your local checkout
./build_release.sh https://api.cblrep.ph
# -> build/app/outputs/flutter-apk/app-release.apk
```

The script refuses to build without an `https://` argument, so a stray
`flutter build apk --release` cannot silently ship a placeholder host. Verify the
baked origin:

```bash
strings build/app/outputs/flutter-apk/app-release.apk \
  | grep -o 'https://api.cblrep.ph' | head -1
```

Distribute `app-release.apk` (GitHub release, or direct install). On the phone:
allow "install from unknown sources", then open the APK and sign in.

---

## 12. Update / redeploy

```bash
cd /var/www/cblrep
git fetch origin
git checkout integration && git pull        # or your chosen branch

cd backend
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache && php artisan view:cache

cd ../frontend
npm ci && npm run build

sudo systemctl reload php8.3-fpm nginx
```

---

## 13. Backups

```bash
# Database
sudo mariadb-dump `community-based-portal` | gzip > cblrep-db-$(date +%F).sql.gz

# Uploaded media + app config
sudo tar czf cblrep-storage-$(date +%F).tar.gz -C /var/www/cblrep/backend storage/app
```

Schedule both with cron/systemd timers, and copy them off the server. Keep the
`.env` (with `APP_KEY`) in your secrets store — without it, encrypted 2FA secrets
cannot be recovered.

---

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `502 Bad Gateway` on `/api` | PHP-FPM running? Socket path in the nginx block matches `ls /run/php/`? |
| `/admin/...` returns 404 on refresh | The `location /` fallback must exist; confirm `frontend/dist/index.html` is built. |
| Console loads but shows no data | API reachable? Open devtools → Network → `/api/...`; check `storage/logs/laravel.log`. |
| `SQLSTATE... Unknown database` | DB name hyphen must be back-ticked; check `DB_DATABASE`. |
| `The MAC is invalid` / 2FA broken | `APP_KEY` changed after migrating an existing DB. Restore the original key. |
| Photos 404 | `php artisan storage:link` not run, or `location /storage/` missing. |
| Certbot fails | DNS `api.cblrep.ph` not resolving to this server, or port 80 blocked. |
