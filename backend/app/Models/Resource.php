<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Frontend "listings" are persisted as resources (see Listing model).
 */
class Resource extends Model
{
    /**
     * The three community-sharing modes a listing can declare.
     *
     *   FREE   — a gift to a neighbour; never carries a price.
     *   BARTER — an item/skill swap; negotiated directly, no price.
     *   PAID   — a priced sale; always carries a price.
     */
    public const FREE = 'free';
    public const BARTER = 'barter';
    public const PAID = 'paid';

    public const COMPENSATIONS = [self::FREE, self::BARTER, self::PAID];

    /** Human labels shown on badges in the admin console and mobile app. */
    public const COMPENSATION_LABELS = [
        self::FREE => 'FREE SHARING',
        self::BARTER => 'BARTER',
        self::PAID => 'PAID',
    ];

    protected $fillable = [
        'user_id',
        'category_id',
        'type',
        'compensation_type',
        'wanted_item',
        'price',
        'condition',
        'title',
        'description',
        'location',
        'barangay',
        'purok_sitio',
        'latitude',
        'longitude',
        'is_active',
        'status',
        'image_path',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'price' => 'float',
    ];

    /** Canonical compensation key, defaulting legacy rows to barter. */
    public function compensationType(): string
    {
        $type = $this->compensation_type;

        return in_array($type, self::COMPENSATIONS, true) ? $type : self::BARTER;
    }

    /** Badge text, e.g. "FREE SHARING". */
    public function compensationLabel(): string
    {
        return self::COMPENSATION_LABELS[$this->compensationType()] ?? 'BARTER';
    }

    /**
     * Price is meaningful only for a paid listing — free/barter always report
     * null so the UI never shows a stale figure on a non-sale.
     */
    public function displayPrice(): ?float
    {
        return $this->compensationType() === self::PAID && $this->price !== null
            ? (float) $this->price
            : null;
    }

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
            'compensation_type' => $this->compensationType(),
            'compensation_label' => $this->compensationLabel(),
            // What the owner wants back. Null for free/paid — they have no
            // return side — so the UI can render "Wants: …" only on barter.
            'wanted_item' => $this->compensationType() === self::BARTER
                ? $this->wanted_item
                : null,
            'price' => $this->displayPrice(),
            'condition' => $this->condition ?? 'Good',
            'location' => $this->location ?? '',
            'barangay' => $this->barangay,
            'purok_sitio' => $this->purok_sitio,
            'latitude' => $this->latitude ?? \App\Support\BarangayLocations::for($this->location)[0],
            'longitude' => $this->longitude ?? \App\Support\BarangayLocations::for($this->location)[1],
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
