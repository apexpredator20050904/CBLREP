<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Barangays;
use App\Support\Puroks;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Location and identity validation rules.
 *
 * The portal's scope is fixed: the 20 official barangays of Trinidad, Bohol,
 * with a purok/sitio inside one of them. Nothing in the schema should accept
 * a municipality-wide or out-of-scope value.
 */
class BarangayValidationTest extends TestCase
{
    use RefreshDatabase;

    /** Every official barangay, asserted against the single source of truth. */
    public function test_the_registry_holds_exactly_twenty_official_barangays(): void
    {
        $this->assertCount(20, Barangays::ALL);
        $this->assertSame(count(Barangays::ALL), count(array_unique(Barangays::ALL)), 'No duplicates.');

        foreach (Barangays::ALL as $barangay) {
            $this->assertTrue(Barangays::isValid($barangay), "$barangay should be valid.");
        }
    }

    public function test_out_of_scope_locations_are_rejected(): void
    {
        foreach (['Manila', 'Cebu City', 'Tagbilaran', 'Poblacion, Trinidad', 'not-a-place', ''] as $bad) {
            $this->assertFalse(Barangays::isValid($bad), "\"$bad\" must not validate.");
        }
    }

    public function test_purok_rule_requires_a_designation_and_rejects_municipal_scope(): void
    {
        // Valid: a named purok or sitio.
        $this->assertTrue(Puroks::isValid('Purok 3'));
        $this->assertTrue(Puroks::isValid('Purok Poblacion Norte'));
        $this->assertTrue(Puroks::isValid('Sitio Cadapdapan'));

        // Invalid: no designation, or municipal scope leaking into the field.
        $this->assertFalse(Puroks::isValid(''));
        $this->assertFalse(Puroks::isValid('3'), 'A bare number is not a designation.');
        $this->assertFalse(Puroks::isValid('Barangay Poblacion'));
        $this->assertFalse(Puroks::isValid('Purok 3, Trinidad, Bohol'));
    }

    public function test_registration_rejects_a_duplicate_full_name_case_insensitively(): void
    {
        User::create([
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
        ]);

        $this->postJson('/api/register', [
            'fullName' => 'JUAN DELA CRUZ',
            'email' => 'other@example.test',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 1',
            'password' => 'secret1234',
        ])->assertStatus(422);
    }

    public function test_registration_rejects_a_duplicate_email(): void
    {
        User::create([
            'name' => 'Someone',
            'email' => 'dupe@example.test',
            'password' => bcrypt('secret1234'),
            'role' => 'user',
        ]);

        $this->postJson('/api/register', [
            'fullName' => 'Different Name',
            'email' => 'dupe@example.test',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'Purok 1',
            'password' => 'secret1234',
        ])->assertStatus(422);
    }

    public function test_registration_accepts_a_valid_member(): void
    {
        $this->postJson('/api/register', [
            'fullName' => 'Ana Villanueva',
            'email' => 'ana@example.test',
            'barangay' => 'Tagum Norte',
            'purok_sitio' => 'Purok 2',
            'password' => 'secret1234',
        ])->assertCreated();

        $this->assertDatabaseHas('users', ['email' => 'ana@example.test']);
    }

    public function test_registration_rejects_a_barangay_outside_trinidad(): void
    {
        $this->postJson('/api/register', [
            'fullName' => 'Ana Villanueva',
            'email' => 'ana2@example.test',
            'barangay' => 'Manila',
            'purok_sitio' => 'Purok 2',
            'password' => 'secret1234',
        ])->assertStatus(422);
    }
}
