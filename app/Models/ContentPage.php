<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Municipal content page (admin-managed).
 *
 * Trinidad-specific guides / articles published by admins under a custom
 * URL slug, e.g. slug "waste-segregation-guide". Drafts stay hidden from
 * the public catalogue until published.
 */
class ContentPage extends Model
{
    protected $fillable = [
        'title',
        'slug',
        'body',
        'status',
        'created_by',
        'published_at',
    ];

    protected $casts = [
        'published_at' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function author()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    // ------------------------------------------------------------------
    // Query helpers
    // ------------------------------------------------------------------

    public function scopePublished($query)
    {
        return $query->where('status', 'published');
    }
}
