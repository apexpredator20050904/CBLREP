<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Frontend "listings" are persisted as resources (see Listing model).
 */
class Resource extends Model
{
    protected $fillable = [
        'user_id',
        'category_id',
        'type',
        'exchange_type',
        'condition',
        'title',
        'description',
        'location',
        'is_active',
        'status',
        'image_path',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    public function exchanges()
    {
        return $this->hasMany(Exchange::class);
    }

    // ------------------------------------------------------------------
    // Frontend shape (consumed by Dashboard / listings pages)
    // ------------------------------------------------------------------

    public function toFrontendListing(): array
    {
        return [
            'id' => $this->id,
            'title' => $this->title,
            'description' => $this->description ?? '',
            'category' => $this->category?->name ?? 'Tools',
            'category_id' => $this->category_id,
            'type' => $this->type ?? 'offer',
            'exchange_type' => $this->exchange_type ?? 'Lend',
            'condition' => $this->condition ?? 'Good',
            'location' => $this->location ?? '',
            'status' => $this->status ?? 'active',
            'is_active' => (bool) $this->is_active,
            'owner' => [
                'id' => $this->user?->id,
                'name' => $this->user?->name ?? 'Member',
            ],
            'user_id' => $this->user_id,
            'created_at' => (int) ($this->created_at?->getTimestamp() ?? time()) * 1000,
            'image_url' => $this->image_path ? asset('storage/'.$this->image_path) : null,
        ];
    }
}
