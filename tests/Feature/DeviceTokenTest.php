<?php

namespace Tests\Feature;

use App\Models\DeviceToken;
use App\Models\User;
use Tests\TestCase;

/**
 * FCM device-token registration and removal.
 *
 * Pins the two rules the mobile app relies on:
 *   1. A token always maps to exactly one member — re-registering the same
 *      token reassigns it, so a shared device stops receiving the previous
 *      member's pushes.
 *   2. A member can only remove their own token.
 */
class DeviceTokenTest extends TestCase
{
    private function user(string $name, string $email): User
    {
        return User::create([
            'name' => $name,
            'email' => $email,
            'password' => bcrypt('secret1234'),
            'role' => 'user',
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
        ]);
    }

    public function test_a_member_can_register_a_device_token(): void
    {
        $member = $this->user('Member '.uniqid(), 'member-'.uniqid().'@example.test');
        $token = 'tok-'.uniqid();

        $this->actingAs($member)
            ->postJson('/api/device-tokens', ['token' => $token, 'platform' => 'android'])
            ->assertCreated();

        $this->assertDatabaseHas('device_tokens', [
            'user_id' => $member->id,
            'token' => $token,
            'platform' => 'android',
        ]);
    }

    public function test_registering_the_same_token_reassigns_it_to_the_latest_member(): void
    {
        $first = $this->user('First '.uniqid(), 'first-'.uniqid().'@example.test');
        $second = $this->user('Second '.uniqid(), 'second-'.uniqid().'@example.test');
        $token = 'tok-'.uniqid();

        $this->actingAs($first)->postJson('/api/device-tokens', ['token' => $token])->assertCreated();
        $this->actingAs($second)->postJson('/api/device-tokens', ['token' => $token])->assertCreated();

        $this->assertSame(1, DeviceToken::where('token', $token)->count());
        $this->assertDatabaseHas('device_tokens', ['token' => $token, 'user_id' => $second->id]);
    }

    public function test_a_member_can_remove_their_device_token(): void
    {
        $member = $this->user('Member '.uniqid(), 'member-'.uniqid().'@example.test');
        $token = 'tok-'.uniqid();

        $this->actingAs($member)->postJson('/api/device-tokens', ['token' => $token])->assertCreated();
        $this->actingAs($member)
            ->deleteJson('/api/device-tokens', ['token' => $token])
            ->assertOk();

        $this->assertDatabaseMissing('device_tokens', ['token' => $token]);
    }

    public function test_a_member_cannot_remove_another_members_token(): void
    {
        $owner = $this->user('Owner '.uniqid(), 'owner-'.uniqid().'@example.test');
        $other = $this->user('Other '.uniqid(), 'other-'.uniqid().'@example.test');
        $token = 'tok-'.uniqid();

        $this->actingAs($owner)->postJson('/api/device-tokens', ['token' => $token])->assertCreated();
        $this->actingAs($other)->deleteJson('/api/device-tokens', ['token' => $token])->assertOk();

        $this->assertDatabaseHas('device_tokens', ['token' => $token, 'user_id' => $owner->id]);
    }

    public function test_a_token_is_required(): void
    {
        $member = $this->user('Member '.uniqid(), 'member-'.uniqid().'@example.test');

        $this->actingAs($member)
            ->postJson('/api/device-tokens', ['platform' => 'android'])
            ->assertStatus(422);
    }
}
