<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

class BackendConfigurationTest extends TestCase
{
    public function test_phpunit_configuration_loads(): void
    {
        $this->assertFileExists(__DIR__.'/../../phpunit.xml');
    }
}
