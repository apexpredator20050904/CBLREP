<?php

namespace Tests;

use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use PDO;
use PDOException;

/**
 * Base class for tests that need the application booted (HTTP requests,
 * Eloquent against a real schema, middleware, routing).
 *
 * WHY DatabaseTransactions AND NOT RefreshDatabase
 *
 * This suite runs against the development database (see phpunit.xml — the
 * SQLite default is unusable here because pdo_sqlite is absent and one
 * migration uses MariaDB-only DDL).
 *
 * RefreshDatabase calls `migrate:fresh`, whose dropAllTables() lists every
 * table in the schema with no table-prefix exemption. Pointing that at the
 * development database would destroy its rows. DatabaseTransactions instead
 * wraps each test in a transaction and rolls it back, so the schema and the
 * existing data are left exactly as they were.
 *
 * DO NOT switch these tests to RefreshDatabase while they target the
 * development database. Use a dedicated *_test schema first.
 */
abstract class TestCase extends BaseTestCase
{
    use DatabaseTransactions;

    /**
     * Skips DB-backed tests when the configured database is unreachable, so a
     * credential typo surfaces as a clear message rather than a stack trace.
     */
    protected function setUp(): void
    {
        if (! self::database_reachable()) {
            $this->markTestSkipped(
                'Database unreachable ('.self::database_label().'). '
                .'Check the DB_* values in backend/.env.'
            );
        }

        parent::setUp();
    }

    /** Plain PDO probe, run before the application boots. */
    private static function database_reachable(): bool
    {
        static $reachable = null;

        if ($reachable !== null) {
            return $reachable;
        }

        // The DB password is intentionally absent from phpunit.xml (it is a
        // secret and used to be committed there). When PHPUnit has not put it
        // into the process environment, fall back to the application's own
        // .env / .env.testing so a plain `php artisan test` still connects.
        self::load_application_env();

        $host = self::env_value('DB_HOST') ?: '127.0.0.1';
        $port = self::env_value('DB_PORT') ?: '3306';
        $database = self::env_value('DB_DATABASE');
        $username = self::env_value('DB_USERNAME');
        $password = self::env_value('DB_PASSWORD');

        if ($database === ':memory:') {
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

    /**
     * Loads .env.testing / .env into $_ENV and $_SERVER without overriding
     * anything PHPUnit already set (APP_ENV=testing, DB_HOST, ...). Mirrors
     * the framework's own bootstrap just early enough for the PDO probe.
     */
    private static function load_application_env(): void
    {
        static $loaded = false;

        if ($loaded) {
            return;
        }

        $loaded = true;
        $base = dirname(__DIR__);
        $file = is_file($base.'/.env.testing') ? '.env.testing' : '.env';

        if (is_file($base.'/'.$file) && class_exists(\Dotenv\Dotenv::class)) {
            try {
                \Dotenv\Dotenv::createImmutable($base, $file)->safeLoad();
            } catch (\Throwable) {
                // Fall through: the probe reports unreachable with a clear note.
            }
        }
    }

    /** Reads an env value from the process env, then the loaded $_ENV/$_SERVER. */
    private static function env_value(string $key): string
    {
        foreach ([getenv($key), $_ENV[$key] ?? null, $_SERVER[$key] ?? null] as $value) {
            if (is_string($value) && $value !== '') {
                return $value;
            }
        }

        return '';
    }

    private static function database_label(): string
    {
        return sprintf(
            '%s:%s/%s as %s',
            self::env_value('DB_HOST') ?: '127.0.0.1',
            self::env_value('DB_PORT') ?: '3306',
            self::env_value('DB_DATABASE') ?: '(unset)',
            self::env_value('DB_USERNAME') ?: '(unset)',
        );
    }

    /**
     * Row count of a table *before* the test adds anything.
     *
     * These tests share the development database, which already holds real
     * rows. Any assertion of the form "this endpoint returns exactly N rows"
     * therefore has to be expressed relative to that baseline — an absolute
     * count would be wrong on a populated database and quietly wrong in the
     * other direction on an empty one.
     */
    protected function baseline(string $table): int
    {
        return $this->getConnection()->table($table)->count();
    }

    /** Runs a callback with foreign-key checks suspended, restoring them after. */
    protected function withoutForeignKeys(callable $callback): mixed
    {
        $connection = $this->getConnection();
        $connection->statement('SET FOREIGN_KEY_CHECKS=0');

        try {
            return $callback();
        } finally {
            $connection->statement('SET FOREIGN_KEY_CHECKS=1');
        }
    }

    /** Removes every row from the given tables, leaving the schema intact. */
    protected function emptyTables(string ...$tables): void
    {
        $this->withoutForeignKeys(function () use ($tables) {
            foreach ($tables as $table) {
                $this->getConnection()->table($table)->delete();
            }
        });
    }
}
