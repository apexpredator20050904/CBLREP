<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use PDO;
use PDOException;

/**
 * Base class for tests that need the application booted (HTTP requests,
 * Eloquent against a real schema, middleware, routing).
 *
 * Unit tests that need nothing but plain assertions may extend
 * PHPUnit\Framework\TestCase directly instead.
 */
abstract class TestCase extends BaseTestCase
{
    /**
     * Skips DB-backed tests when the dedicated test database is unreachable.
     *
     * The suite targets a real MariaDB/MySQL schema rather than SQLite,
     * because migration 2026_10_04_000002 uses engine-specific DDL (a STORED
     * generated column plus a plain unique index — MariaDB has no
     * functional-key index). That requires a separate database the app user
     * can reach:
     *
     *   CREATE DATABASE `community-based-portal_test`
     *     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
     *   GRANT ALL PRIVILEGES ON `community-based-portal_test`.*
     *     TO 'cblrep'@'localhost';
     *   FLUSH PRIVILEGES;
     *
     * Until that grant exists these tests skip instead of failing — and never
     * fall back to the development database, which RefreshDatabase would
     * otherwise drop.
     *
     * The probe runs BEFORE parent::setUp(), because RefreshDatabase
     * migrates as part of setUp and would throw first.
     */
    protected function setUp(): void
    {
        if (! self::test_database_reachable()) {
            $this->markTestSkipped(
                'Test database unreachable. Create `community-based-portal_test` and grant '
                .'the app user access — see backend/tests/TestCase.php.'
            );
        }

        parent::setUp();
    }

    /**
     * Plain PDO probe against the configured test database.
     *
     * Reads the phpunit.xml env values directly because the application is not
     * booted yet at this point.
     */
    private static function test_database_reachable(): bool
    {
        static $reachable = null;

        if ($reachable !== null) {
            return $reachable;
        }

        $host = getenv('DB_HOST') ?: '127.0.0.1';
        $port = getenv('DB_PORT') ?: '3306';
        $database = getenv('DB_DATABASE') ?: '';
        $username = getenv('DB_USERNAME') ?: '';
        $password = (string) (getenv('DB_PASSWORD') ?: '');

        if ($database === '' || $database === ':memory:') {
            // SQLite in-memory: nothing to reach, let the parent handle it.
            return $reachable = true;
        }

        try {
            new PDO(
                "mysql:host={$host};port={$port};dbname={$database}",
                $username,
                $password,
                [PDO::ATTR_TIMEOUT => 3]
            );
            $reachable = true;
        } catch (PDOException) {
            $reachable = false;
        }

        return $reachable;
    }
}
