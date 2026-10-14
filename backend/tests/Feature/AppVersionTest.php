<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * GET /api/app-version — the mobile release channel.
 *
 * Pins the contract the Flutter updater depends on:
 *   1. The endpoint is reachable with no token (an outdated build must be able
 *      to learn about its replacement before sign-in).
 *   2. It echoes the configured release metadata verbatim, including an EMPTY
 *      apk_url, which the client treats as "update channel off".
 *
 * Values are injected through the config repository so the suite never depends
 * on whatever real release happens to be configured in .env.
 */
class AppVersionTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config()->set('app_version.version_code', 7);
        config()->set('app_version.version_name', '9.9.9');
        config()->set('app_version.min_supported_code', 5);
        config()->set('app_version.apk_url', 'https://example.test/app-release.apk');
        config()->set('app_version.sha256', 'abc123');
        config()->set('app_version.notes', 'Listing lifecycle + push fixes');
    }

    public function test_it_serves_release_metadata_without_a_token(): void
    {
        $this->getJson('/api/app-version')
            ->assertOk()
            ->assertExactJson([
                'version_code' => 7,
                'version_name' => '9.9.9',
                'min_supported_code' => 5,
                'apk_url' => 'https://example.test/app-release.apk',
                'sha256' => 'abc123',
                'notes' => 'Listing lifecycle + push fixes',
            ]);
    }

    public function test_an_empty_apk_url_disables_the_update_channel(): void
    {
        config()->set('app_version.apk_url', '');

        $response = $this->getJson('/api/app-version')->assertOk();

        // The client keys "no update" off an empty URL, so it must survive the
        // round trip as an empty string rather than null.
        $this->assertSame('', $response->json('apk_url'));
    }
}
