<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Demo accounts matching the credentials shown on the login screens:
     *   Admin  — admin@cblrep.ph / admin123        (AdminLogin.jsx)
     *   Member — maria.santos@cblrep.ph / member123
     */
    public function run(): void
    {
        $admin = User::updateOrCreate(
            ['email' => 'admin@cblrep.ph'],
            [
                'name' => 'System Administrator',
                'password' => 'admin123',
                'role' => 'admin',
                'is_verified' => true,
                'barangay_or_location' => 'Barangay 1',
                'time_bank_credits' => 18.5,
            ]
        );
        $admin->forceFill([
            'verification_status' => 'verified',
            'account_status' => 'active',
        ])->save();

        $member = User::updateOrCreate(
            ['email' => 'maria.santos@cblrep.ph'],
            [
                'name' => 'Maria Santos',
                'password' => 'member123',
                'role' => 'user',
                'is_verified' => true,
                'barangay_or_location' => 'Barangay 14',
                'time_bank_credits' => 4.8,
            ]
        );
        $member->forceFill([
            'verification_status' => 'verified',
            'account_status' => 'active',
        ])->save();

        $studentMember = User::updateOrCreate(
            ['email' => 'juan.delacruz@cblrep.ph'],
            [
                'name' => 'Juan Dela Cruz',
                'password' => 'member123',
                'role' => 'user',
                'is_verified' => true,
                'barangay_or_location' => 'Banlasan',
                'student_status' => true,
                'student_school' => 'University of Bohol',
                'time_bank_credits' => 2.5,
            ]
        );
        $studentMember->forceFill([
            'verification_status' => 'verified',
            'account_status' => 'active',
        ])->save();
    }
}
