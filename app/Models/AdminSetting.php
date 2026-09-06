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
}
