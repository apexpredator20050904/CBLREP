<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PrivacyConsentTest extends TestCase
{
    public function test_registration_requires_privacy_consent(): void
    {
        $email = uniqid('privacy-').'@example.test';

        $response = $this->postJson('/api/register', [
            'fullName' => 'Privacy Member '.uniqid(),
            'email' => $email,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'password' => 'secret1234',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('privacy_consent');

        $this->assertDatabaseMissing('users', ['email' => $email]);
    }

    public function test_registration_records_accepted_privacy_consent(): void
    {
        $email = uniqid('privacy-').'@example.test';

        $response = $this->postJson('/api/register', [
            'fullName' => 'Privacy Member '.uniqid(),
            'email' => $email,
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'password' => 'secret1234',
            'privacy_consent' => true,
        ]);
        $response->assertCreated()->assertJsonPath('user.privacy_consent_version', '1.0');
        $this->assertNotEmpty($response->json('user.privacy_consent_at'));

        $this->assertDatabaseHas('users', [
            'email' => $email,
            'privacy_consent_version' => '1.0',
        ]);
        $this->assertNotNull(User::where('email', $email)->value('privacy_consent_at'));
    }

    public function test_verification_requires_privacy_consent(): void
    {
        Storage::fake('local');
        $member = $this->member();

        $this->actingAs($member)->post('/api/verification', [
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'document_type' => 'Barangay certificate',
            'document' => UploadedFile::fake()->create('proof.jpg', 10, 'image/jpeg'),
        ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('privacy_consent');

        $this->assertNull($member->fresh()->privacy_consent_at);
    }

    public function test_verification_records_accepted_privacy_consent(): void
    {
        Storage::fake('local');
        $member = $this->member();

        $this->actingAs($member)->post('/api/verification', [
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
            'document_type' => 'Barangay certificate',
            'document' => UploadedFile::fake()->create('proof.jpg', 10, 'image/jpeg'),
            'privacy_consent' => true,
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('user.privacy_consent_version', '1.0');

        $this->assertNotNull($member->fresh()->privacy_consent_at);
        $this->assertSame('1.0', $member->fresh()->privacy_consent_version);
    }

    private function member(): User
    {
        return User::create([
            'name' => 'Privacy Member '.uniqid(),
            'email' => uniqid('privacy-member-').'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => User::ROLE_USER,
            'barangay' => 'Poblacion',
            'barangay_or_location' => 'Poblacion',
            'purok_sitio' => 'Purok 3',
        ]);
    }
}
