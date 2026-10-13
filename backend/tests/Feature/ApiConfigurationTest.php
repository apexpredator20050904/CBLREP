<?php

namespace Tests\Feature;

use PHPUnit\Framework\TestCase;

class ApiConfigurationTest extends TestCase
{
    public function test_api_routes_file_exists(): void
    {
        $this->assertFileExists(__DIR__.'/../../routes/api.php');
    }
}
