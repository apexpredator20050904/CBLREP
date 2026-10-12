<?php

namespace Database\Seeders;

use App\Models\User;
use App\Support\TotpService;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    /**
     * The single authorised Super Administrator account.
     *
     * This is the ONLY account that can access the admin panel. No other
     * admin or super_admin accounts may exist in the system.
     */
    private const SUPER_ADMIN_EMAIL = 'admin@cblrep.ph';
    private const SUPER_ADMIN_PASSWORD = 'adminpass123';
    private const SUPER_ADMIN_NAME = 'System Administrator';

    /**
     * Purge all application data and seed a single Super Admin account.
     *
     * Steps:
     *   1. Disable foreign key checks (allows truncating in any order)
     *   2. Truncate every application table — users, resources, exchanges,
     *      conversations, messages, notifications, audit logs, settings, etc.
     *   3. Re-enable foreign key checks
     *   4. Create the one Super Admin with TOTP 2FA enrolled
     *
     * The result is a pristine production-ready state: exactly one user,
     * zero listings, zero exchanges, zero conversations.
     */
    public function run(): void
    {
        $this->purgeAllTables();
        $this->seedSuperAdmin();
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
     * Create the single Super Admin account with TOTP 2FA enrolled.
     *
     * The account is created with:
     *   - super_admin role (full administrative privileges)
     *   - Bcrypt-hashed password
     *   - TOTP secret for authenticator app enrolment
     *   - Recovery codes (digests stored, plaintext shown once)
     *
     * No other accounts are created. The system starts with exactly one
     * user and zero content.
     */
    private function seedSuperAdmin(): void
    {
        $totp = app(TotpService::class);
        $secret = $totp->generateSecret();
        [$plainCodes, $digests] = $totp->generateRecoveryCodes();

        $user = User::create([
            'name' => self::SUPER_ADMIN_NAME,
            'email' => self::SUPER_ADMIN_EMAIL,
            'password' => Hash::make(self::SUPER_ADMIN_PASSWORD),
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
        $this->command->info("  Email:    {$user->email}");
        $this->command->info("  Password: " . self::SUPER_ADMIN_PASSWORD);
        $this->command->info("  Role:     {$user->role}");
        $this->command->info("  2FA:      Enrolled (TOTP)");
        $this->command->info("  Secret:   {$secret}");
        $this->command->info('─────────────────────────────────────────────');
        $this->command->info('  Recovery codes (save these — shown once):');
        foreach ($plainCodes as $code) {
            $this->command->info("    {$code}");
        }
        $this->command->info('─────────────────────────────────────────────');
        $this->command->warn('  This is the ONLY account in the system.');
        $this->command->warn('  No other admin accounts may be created.');
    }
}
