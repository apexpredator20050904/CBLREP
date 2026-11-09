<?php

namespace Tests\Feature;

use App\Http\Middleware\AdminMiddleware;
use App\Models\User;
use Tests\TestCase;

/**
 * Role-based authorization for /api/admin/*.
 *
 * The console used to be locked to one e-mail address, which made the
 * advertised admin tier unreachable. These tests pin the replacement:
 *   - admin and super_admin may enter the console,
 *   - only super_admin may change roles or delete accounts,
 *   - an ordinary member is refused,
 *   - a suspended admin is refused, and
 *   - an admin who has enrolled in TOTP needs a token minted by the 2FA
 *     verification endpoint (the same rule as before).
 */
class AdminAuthorizationTest extends TestCase
{
    private function user(string $role, array $attributes = []): User
    {
        return User::create(array_merge([
            'name' => ucfirst($role).' '.uniqid(),
            'email' => $role.'-'.uniqid().'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => $role,
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 1',
        ], $attributes));
    }

    /** A bearer token accepted by the admin route group. */
    private function tokenFor(User $user, string $name = AdminMiddleware::TWO_FACTOR_TOKEN): string
    {
        return $user->createToken($name)->plainTextToken;
    }

    // ------------------------------------------------------------------
    // Entry
    // ------------------------------------------------------------------

    public function test_an_admin_can_reach_the_admin_users_endpoint(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);

        $this->withToken($this->tokenFor($admin))
            ->getJson('/api/admin/users')
            ->assertOk()
            ->assertJsonStructure(['users', 'total']);
    }

    public function test_a_super_admin_can_reach_the_admin_users_endpoint(): void
    {
        $superAdmin = $this->user(User::ROLE_SUPER_ADMIN);

        $this->withToken($this->tokenFor($superAdmin))
            ->getJson('/api/admin/users')
            ->assertOk();
    }

    public function test_a_normal_member_is_forbidden(): void
    {
        $member = $this->user(User::ROLE_USER);

        $this->withToken($this->tokenFor($member))
            ->getJson('/api/admin/users')
            ->assertForbidden();
    }

    public function test_a_suspended_admin_is_forbidden(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);
        // account_status is intentionally not mass-assignable, like the other
        // lifecycle columns an administrator controls directly.
        $admin->account_status = 'suspended';
        $admin->save();

        $this->withToken($this->tokenFor($admin))
            ->getJson('/api/admin/users')
            ->assertForbidden();
    }

    // ------------------------------------------------------------------
    // Destructive and role-changing actions
    // ------------------------------------------------------------------

    public function test_an_admin_cannot_change_a_role(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);
        $member = $this->user(User::ROLE_USER);

        $this->withToken($this->tokenFor($admin))
            ->patchJson("/api/admin/accounts/{$member->id}/role", ['role' => User::ROLE_ADMIN])
            ->assertForbidden();

        $this->assertSame(User::ROLE_USER, $member->fresh()->role);
    }

    public function test_an_admin_cannot_delete_an_account(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);
        $member = $this->user(User::ROLE_USER);

        $this->withToken($this->tokenFor($admin))
            ->deleteJson("/api/admin/accounts/{$member->id}")
            ->assertForbidden();

        $this->assertDatabaseHas('users', ['id' => $member->id]);
    }

    public function test_a_super_admin_can_change_a_role(): void
    {
        $superAdmin = $this->user(User::ROLE_SUPER_ADMIN);
        $member = $this->user(User::ROLE_USER);

        $this->withToken($this->tokenFor($superAdmin))
            ->patchJson("/api/admin/accounts/{$member->id}/role", ['role' => User::ROLE_ADMIN])
            ->assertOk()
            ->assertJsonPath('user.raw_role', User::ROLE_ADMIN);

        $this->assertSame(User::ROLE_ADMIN, $member->fresh()->role);
    }

    public function test_a_super_admin_can_delete_an_account(): void
    {
        $superAdmin = $this->user(User::ROLE_SUPER_ADMIN);
        $member = $this->user(User::ROLE_USER);

        $this->withToken($this->tokenFor($superAdmin))
            ->deleteJson("/api/admin/accounts/{$member->id}")
            ->assertOk();

        $this->assertDatabaseMissing('users', ['id' => $member->id]);
    }

    // ------------------------------------------------------------------
    // Second factor
    // ------------------------------------------------------------------

    public function test_an_enrolled_admin_is_forbidden_without_a_two_factor_token(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);
        $admin->forceFill([
            'two_factor_enabled' => true,
            'two_factor_secret' => 'JBSWY3DPEHPK3PXP',
            'two_factor_confirmed_at' => now(),
        ])->save();

        // A token minted by the ordinary member login path is not enough.
        $this->withToken($this->tokenFor($admin, 'cblrep-member'))
            ->getJson('/api/admin/users')
            ->assertForbidden();
    }

    public function test_an_enrolled_admin_is_allowed_with_a_two_factor_token(): void
    {
        $admin = $this->user(User::ROLE_ADMIN);
        $admin->forceFill([
            'two_factor_enabled' => true,
            'two_factor_secret' => 'JBSWY3DPEHPK3PXP',
            'two_factor_confirmed_at' => now(),
        ])->save();

        // The token minted by AdminTwoFactorController::verify() is.
        $this->withToken($this->tokenFor($admin, AdminMiddleware::TWO_FACTOR_TOKEN))
            ->getJson('/api/admin/users')
            ->assertOk();
    }
}
