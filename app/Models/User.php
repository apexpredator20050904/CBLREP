<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, Notifiable;

        protected $fillable = [
        'name',
        'email',
        'password',
        'role',
        'is_verified',
        'barangay_or_location',
        'student_status',
        'student_school',
        'time_bank_credits',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

        protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_verified' => 'boolean',
            'student_status' => 'boolean',
            'time_bank_credits' => 'float',
        ];
    }

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function resources()
    {
        return $this->hasMany(Resource::class);
    }

    // ------------------------------------------------------------------
    // Helpers used by the admin controllers
    // ------------------------------------------------------------------

    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }

    public function verificationStatusLabel(): string
    {
        return match ($this->verification_status) {
            'verified' => 'Verified',
            'rejected' => 'Rejected',
            default => 'Pending',
        };
    }

    public function accountStatusLabel(): string
    {
        return match ($this->account_status) {
            'suspended' => 'Suspended',
            default => 'Active',
        };
    }

    /**
     * Shape consumed by the admin users pages.
     */
        public function toFrontendArray(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'fullName' => $this->name,
            'email' => $this->email,
            'role' => $this->isAdmin() ? 'System Administrator' : 'General Member',
            'raw_role' => $this->role,
            'is_verified' => (bool) $this->is_verified,
            'verification_status' => $this->verificationStatusLabel(),
            'account_status' => $this->accountStatusLabel(),
            'time_bank_credits' => (float) $this->time_bank_credits,
            'barangay_or_location' => $this->barangay_or_location,
            'is_student' => (bool) $this->student_status,
            'student_school' => $this->student_school,
            'resources_count' => $this->resources_count ?? $this->resources()->count(),
            'date_registered' => $this->created_at?->format('M j, Y'),
            'created_at' => $this->created_at?->format('M j, Y'),
        ];
    }
}
