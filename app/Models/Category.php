<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Category extends Model
{
    protected $fillable = ['name'];

    /**
     * ListingController stores resources by category name; resolve or create.
     */
    public static function findOrCreateByName(?string $name): self
    {
        $name = trim((string) $name) ?: 'Tools';

        return static::query()->firstOrCreate(['name' => $name]);
    }

    public function resources()
    {
        return $this->hasMany(Resource::class);
    }
}
