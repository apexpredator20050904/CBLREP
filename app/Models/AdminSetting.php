<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AdminSetting extends Model
{
    protected $fillable = ['key', 'value', 'updated_by'];

    public static function get(string $key, bool $default = false): bool
    {
        $row = static::query()->where('key', $key)->first();

        return $row === null ? $default : in_array($row->value, ['1', 'true'], true);
    }

    public static function put(string $key, bool $value, ?string $updatedBy = null): void
    {
        static::updateOrCreate(
            ['key' => $key],
            ['value' => $value ? '1' : '0', 'updated_by' => $updatedBy],
        );
    }

    public static function value(string $key, mixed $default = null): mixed
    {
        $row = static::query()->where('key', $key)->first();

        if ($row === null) {
            return $default;
        }

        $decoded = json_decode((string) $row->value, true);

        return json_last_error() === JSON_ERROR_NONE ? $decoded : $row->value;
    }

    public static function putValue(string $key, mixed $value, ?string $updatedBy = null): void
    {
        static::updateOrCreate(
            ['key' => $key],
            [
                'value' => is_string($value) ? $value : json_encode($value, JSON_THROW_ON_ERROR),
                'updated_by' => $updatedBy,
            ],
        );
    }
}
