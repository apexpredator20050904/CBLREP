# CBLREP — API (Laravel 12)

The JSON API behind the CBLREP portal: members and verification, listings
(offers and needs), the barter ledger, conversations, notifications, reports
and moderation, and the endpoints the admin console drives.

| | |
| --- | --- |
| **Branch** | `back-end` — the source of truth for `backend/` in the monorepo |
| **Stack** | PHP 8.3 · Laravel 12 · Sanctum 4 · MariaDB / MySQL |
| **Runs on** | `http://127.0.0.1:8000/api` locally, behind an ngrok tunnel for phones |
| **Docs** | [RUNNING.md](https://github.com/apexpredator20050904/CBLREP/blob/main/RUNNING.md) · [DEPLOY_DEBIAN.md](https://github.com/apexpredator20050904/CBLREP/blob/main/backend/deploy/DEPLOY_DEBIAN.md) |

## Run it

```bash
composer install
cp .env.example .env && php artisan key:generate

# the database and its user have to exist before the migration
# (see RUNNING.md §2.3)

php artisan migrate --force
php artisan db:seed --force            # creates the administrator
php artisan serve --host=127.0.0.1 --port=8000
```

## Test it

```bash
php artisan test        # 191 tests; needs a current MariaDB schema
```

The seeder prints the administrator's credentials and the TOTP enrolment
secret. The full runbook — the database, the tunnel, test accounts, the
release channel and the production deployment — is in
[RUNNING.md](https://github.com/apexpredator20050904/CBLREP/blob/main/RUNNING.md).
