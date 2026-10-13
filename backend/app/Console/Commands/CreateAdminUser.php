<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\TotpService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

class CreateAdminUser extends Command
{
    protected $signature = 'admin:create
                            {--email= : Admin email address}
                            {--password= : Admin password}
                            {--name= : Admin display name}
                            {--2fa : Enroll TOTP two-factor authentication}';

    protected $description = 'Create an admin user account with optional 2FA enrolment';

    public function handle(): int
    {
        $email = $this->option('email') ?? $this->ask('Admin email address');
        $password = $this->option('password') ?? $this->secret('Admin password');
        $name = $this->option('name') ?? $this->ask('Admin display name', 'System Administrator');
        $enroll2fa = $this->option('2fa') || $this->confirm('Enroll two-factor authentication now?', true);

        // Create or update the user
        $user = User::updateOrCreate(
            ['email' => strtolower($email)],
            [
                'name' => $name,
                'password' => Hash::make($password),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_verified' => true,
                'barangay_or_location' => 'Trinidad, Bohol',
                'verification_status' => 'verified',
                'account_status' => 'active',
            ]
        );

        $this->info("Admin account created: {$user->email}");

        if ($enroll2fa) {
            $totp = app(TotpService::class);
            $secret = $totp->generateSecret();

            // Generate recovery codes
            [$plainCodes, $digests] = $totp->generateRecoveryCodes();

            // Enable 2FA on the user
            $user->two_factor_secret = $secret;
            $user->enableTwoFactor($digests);

            // Generate QR code
            $provisioningUri = $totp->provisioningUri($secret, $user->email);
            $qrCode = $totp->qrCodeDataUri($provisioningUri);

            $this->info('2FA enrolled successfully.');
            $this->newLine();
            $this->info('TOTP Secret: ' . $secret);
            $this->info('Issuer: ' . TotpService::ISSUER);
            $this->newLine();
            $this->info('QR Code (save this image):');
            $this->line($qrCode);
            $this->newLine();
            $this->info('Recovery codes (save these):');
            foreach ($plainCodes as $code) {
                $this->line('  ' . $code);
            }
            $this->newLine();
            $this->warn('Store these recovery codes in a safe place. They will not be shown again.');
        }

        return self::SUCCESS;
    }
}
