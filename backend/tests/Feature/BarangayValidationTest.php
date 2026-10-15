<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Barangays;
use App\Support\Puroks;
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

    /**
     * Members type these by hand, so casing must never decide acceptance, and
     * real Filipino place names carry letters outside ASCII.
     */
    public function test_purok_rule_accepts_any_casing_and_unicode_letters(): void
    {
        foreach ([
            'Purok 3',
            'purok 3',
            'PUROK 3',
            'PuRoK 3',
            'Sitio Cadapdapan',
            'sitio Cadapdapan',
            'SITIO Cadapdapan',
            'Sitio Peña',
            'Sitio Cañada',
            'Sitio Sto. Niño',
            'Purok  Poblacion Norte', // double space
            'Purok3',                  // dropped separator
        ] as $value) {
            $this->assertTrue(Puroks::isValid($value), "\"$value\" should validate.");
        }

        // A name is still required after the designation.
        $this->assertFalse(Puroks::isValid('Purok'));
        $this->assertFalse(Puroks::isValid('purok '));
    }

    public function test_purok_canonicalisation_folds_casing_and_spacing(): void
    {
        $this->assertSame('Purok 3', Puroks::canonicalize('purok 3'));
        $this->assertSame('Purok 3', Puroks::canonicalize('PUROK  3'));
        $this->assertSame('Purok poblacion norte', Puroks::canonicalize('purok  poblacion   norte'));
        $this->assertSame('Sitio Cadapdapan', Puroks::canonicalize('sitio Cadapdapan'));
        $this->assertSame('Purok 3', Puroks::canonicalize('Purok3'));
        $this->assertSame('Sitio Sto. Niño', Puroks::canonicalize('  Sitio   Sto. Niño '));
        // Whatever follows the designation keeps its own casing.
        $this->assertSame('Purok III', Puroks::canonicalize('purok III'));

        $this->assertNull(Puroks::canonicalize(null));
        $this->assertNull(Puroks::canonicalize(''));
        $this->assertNull(Puroks::canonicalize('   '));
    }

    /** Every location-bearing model funnels writes through the same mutator. */
    public function test_location_models_store_a_canonical_purok_sitio(): void
    {
        $user = new User();
        $user->purok_sitio = 'purok 5';
        $this->assertSame('Purok 5', $user->purok_sitio);

        $resource = new \App\Models\Resource();
        $resource->purok_sitio = 'sitio  peña';
        $this->assertSame('Sitio peña', $resource->purok_sitio);

        $exchange = new \App\Models\Exchange();
        $exchange->purok_sitio = 'PUROK   Poblacion   Norte';
        $this->assertSame('Purok Poblacion Norte', $exchange->purok_sitio);
    }

    public function test_registration_canonicalises_the_stored_purok_sitio(): void
    {
        $this->postJson('/api/register', [
            'fullName' => 'Nena Canonical',
            'email' => 'nena@example.test',
            'barangay' => 'Poblacion',
            'purok_sitio' => 'purok 4',
            'password' => 'secret1234',
        ])->assertCreated();

        $this->assertDatabaseHas('users', [
            'email' => 'nena@example.test',
            'purok_sitio' => 'Purok 4',
        ]);
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
