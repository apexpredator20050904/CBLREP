<?php

namespace Database\Seeders;

use App\Models\User;
use App\Support\TotpService;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

class DatabaseSeeder extends Seeder
{
    /**
     * Local demo fallbacks. Production must set ADMIN_SEED_PASSWORD (and
     * should set ADMIN_SEED_EMAIL too); the seeder refuses to use these when
     * APP_ENV=production.
     */
    private const DEMO_SUPER_ADMIN_EMAIL = 'admin@cblrep.ph';
    private const DEMO_SUPER_ADMIN_PASSWORD = 'adminpass123';
    private const SUPER_ADMIN_NAME = 'System Administrator';

    private string $superAdminEmail = self::DEMO_SUPER_ADMIN_EMAIL;
    private string $superAdminPassword = self::DEMO_SUPER_ADMIN_PASSWORD;

    /**
     * Purge all application data and seed one Super Admin account.
     *
     * Steps:
     *   1. Refuse an unintended production run and resolve the seed credentials
     *   2. Warn that every application table is about to be truncated
     *   3. Disable foreign key checks (allows truncating in any order)
     *   4. Truncate every application table — users, resources, exchanges,
     *      conversations, messages, notifications, audit logs, settings, etc.
     *   5. Re-enable foreign key checks
     *   6. Create a Super Admin with TOTP 2FA enrolled
     *
     * The result is a clean local demo state: one administrator, zero
     * listings, zero exchanges, zero conversations.
     */
    public function run(): void
    {
        $this->guardAgainstUnforcedProductionRun();
        $this->resolveSeedCredentials();

        $this->command?->warn('WARNING: db:seed TRUNCATEs every application table — all users, listings, exchanges, messages and notifications will be deleted.');

        $this->purgeAllTables();
        $this->seedSuperAdmin();
    }

    /**
     * Production runs must be explicit. The framework's own SeedCommand also
     * asks for --force, but keeping the guard here means a production wipe can
     * never happen just because the seeder was invoked programmatically.
     */
    private function guardAgainstUnforcedProductionRun(): void
    {
        if (! app()->environment('production')) {
            return;
        }

        $forced = $this->command !== null
            && $this->command->hasOption('force')
            && (bool) $this->command->option('force');

        if (! $forced) {
            throw new RuntimeException(
                'Refusing to seed in production without --force. This command TRUNCATEs every table.'
            );
        }
    }

    /** Read ADMIN_SEED_* from the environment, falling back only in local. */
    private function resolveSeedCredentials(): void
    {
        $email = trim((string) env('ADMIN_SEED_EMAIL', ''));
        $password = (string) env('ADMIN_SEED_PASSWORD', '');

        if ($email !== '') {
            $this->superAdminEmail = $email;
        }

        if ($password !== '') {
            $this->superAdminPassword = $password;

            return;
        }

        if (app()->environment('production')) {
            throw new RuntimeException(
                'ADMIN_SEED_PASSWORD is not set. Production seeding will not fall back to the local demo password. '
                .'Set ADMIN_SEED_EMAIL and ADMIN_SEED_PASSWORD in backend/.env, or create the account with '
                .'`php artisan admin:create` instead.'
            );
        }

        // Local/demo fallback — never used in production.
        $this->superAdminPassword = self::DEMO_SUPER_ADMIN_PASSWORD;
    }

    /**
     * Truncate every application table, leaving a completely empty database.
     *
     * Tables are truncated (not dropped) so the schema from migrations
     * remains intact. Foreign key checks are disabled during truncation
     * to avoid order-dependent constraint violations.
     */
    private function purgeAllTables(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');

        $tables = [
            // Core application data
            'users',
            'categories',
            'resources',
            'exchanges',
            'conversations',
            'messages',
            'member_notifications',
            'announcements',
            'content_pages',
            'verification_histories',
            'admin_settings',
            'admin_two_factor_challenges',
            'audit_logs',
            'system_logs',

            // Laravel framework tables (clean slate)
            'sessions',
            'cache',
            'cache_locks',
            'jobs',
            'job_batches',
            'failed_jobs',
            'password_reset_tokens',
            'personal_access_tokens',
        ];

        foreach ($tables as $table) {
            DB::table($table)->truncate();
        }

        DB::statement('SET FOREIGN_KEY_CHECKS=1');
    }

    /**
     * Create the initial Super Admin account with TOTP 2FA enrolled.
     *
     * The account is created with:
     *   - super_admin role (full administrative privileges)
     *   - Bcrypt-hashed password from ADMIN_SEED_PASSWORD
     *   - TOTP secret for authenticator app enrolment
     *   - Recovery codes (digests stored, plaintext shown once)
     *
     * More administrator accounts can be added later from the console by a
     * super_admin, or with `php artisan admin:create`.
     */
    private function seedSuperAdmin(): void
    {
        $totp = app(TotpService::class);
        $secret = $totp->generateSecret();
        [$plainCodes, $digests] = $totp->generateRecoveryCodes();

        $user = User::create([
            'name' => self::SUPER_ADMIN_NAME,
            'email' => $this->superAdminEmail,
            'password' => Hash::make($this->superAdminPassword),
            'role' => User::ROLE_SUPER_ADMIN,
            'is_verified' => true,
            'barangay_or_location' => 'Trinidad, Bohol',
            'verification_status' => 'verified',
            'account_status' => 'active',
        ]);

        // Enable 2FA: stores the TOTP secret and recovery code digests.
        // The plaintext recovery codes are shown once in the console output.
        $user->two_factor_secret = $secret;
        $user->enableTwoFactor($digests);

        $this->command->info('─────────────────────────────────────────────');
        $this->command->info('  Super Admin account created successfully');
        $this->command->info('─────────────────────────────────────────────');
        $this->command?->info("  Email:    {$user->email}");
        $this->command?->info("  Password: {$this->superAdminPassword}");
        $this->command?->info("  Role:     {$user->role}");
        $this->command?->info("  2FA:      Enrolled (TOTP)");
        $this->command?->info("  Secret:   {$secret}");
        $this->command?->info('─────────────────────────────────────────────');
        $this->command?->info('  Recovery codes (save these — shown once):');
        foreach ($plainCodes as $code) {
            $this->command?->info("    {$code}");
        }
        $this->command?->info('─────────────────────────────────────────────');
        $this->command?->warn('  Local demo credentials — change ADMIN_SEED_EMAIL / ADMIN_SEED_PASSWORD before any real deployment.');
        $this->command?->warn('  More administrator accounts can be created later by a super_admin.');
    }
}
