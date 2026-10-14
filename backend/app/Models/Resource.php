<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
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

    // ------------------------------------------------------------------
    // Lifecycle vs moderation
    // ------------------------------------------------------------------
    //
    // A listing has ONE status column, but two different people may set it:
    //
    //   * the OWNER moves a listing through its life — pause it while lent out,
    //     mark it traded once a barter completes, file it away in the archive;
    //   * an ADMIN holds a listing back for review — flagged/hidden/removed.
    //
    // Keeping the two vocabularies separate is what makes "a member can only
    // move their own listing" expressible: an owner may never move a listing
    // OUT of a moderation state, otherwise PATCH {status:"active"} would
    // silently undo a moderator's decision.

    /** Owner-controlled lifecycle statuses. */
    public const ACTIVE = 'active';

    public const PAUSED = 'paused';

    public const TRADED = 'traded';

    public const ARCHIVED = 'archived';

    public const LIFECYCLE_STATUSES = [self::ACTIVE, self::PAUSED, self::TRADED, self::ARCHIVED];

    /** Admin-controlled moderation statuses (never owner-settable). */
    public const FLAGGED = 'flagged';

    public const HIDDEN = 'hidden';

    public const REMOVED = 'removed';

    public const MODERATION_STATUSES = ['pending', self::FLAGGED, self::HIDDEN, self::REMOVED];

    /** Badge text for every status, incl. legacy "closed". */
    public const STATUS_LABELS = [
        self::ACTIVE => 'Active',
        self::PAUSED => 'Paused',
        self::TRADED => 'Traded',
        self::ARCHIVED => 'Archived',
        self::FLAGGED => 'Flagged',
        self::HIDDEN => 'Hidden',
        self::REMOVED => 'Removed',
        'pending' => 'Pending',
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

    // ------------------------------------------------------------------
    // Status helpers
    // ------------------------------------------------------------------

    /**
     * Canonical status. Legacy rows stored "closed" for what is now an archive
     * and rows written before the status column existed may be null, so both
     * are folded in here instead of being migrated.
     */
    public function statusKey(): string
    {
        $status = (string) ($this->status ?? '');
        if ($status === '') {
            return $this->is_active ? self::ACTIVE : self::ARCHIVED;
        }

        return $status === 'closed' ? self::ARCHIVED : $status;
    }

    public function isLifecycleStatus(): bool
    {
        return in_array($this->statusKey(), self::LIFECYCLE_STATUSES, true);
    }

    public function isModerationStatus(): bool
    {
        return in_array($this->statusKey(), self::MODERATION_STATUSES, true);
    }

    /** Only the owner may change a listing that is in a lifecycle state. */
    public function ownerControlsStatus(): bool
    {
        return $this->isLifecycleStatus();
    }

    /** Live in the community feed: active AND not mangled by a stale flag. */
    public function isPubliclyVisible(): bool
    {
        return $this->statusKey() === self::ACTIVE && (bool) $this->is_active;
    }

    /**
     * Query twin of [isPubliclyVisible]: the rows the public feed is allowed to
     * return.
     *
     * Defined once, on the model, so the feed query and anything that asserts
     * against it (see PublicListingsFeedTest) cannot drift apart. A "baseline"
     * that counts a different set of rows than the feed returns is exactly how
     * a feed test starts failing for reasons unrelated to the feed.
     */
    public function scopePubliclyVisible(Builder $query): Builder
    {
        return $query->where('is_active', true)->where('status', self::ACTIVE);
    }

    public function statusLabel(): string
    {
        return self::STATUS_LABELS[$this->statusKey()] ?? ucfirst($this->statusKey());
    }

    /**
     * Apply an owner-initiated transition, normalising the legacy "closed"
     * alias and keeping `is_active` in step with the status so the feed query
     * and the status column can never disagree.
     */
    public function applyOwnerStatus(string $status): void
    {
        $normalized = $status === 'closed' ? self::ARCHIVED : $status;
        if (! in_array($normalized, self::LIFECYCLE_STATUSES, true)) {
            return;
        }
        $this->status = $normalized;
        $this->is_active = $normalized === self::ACTIVE;
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
            'status' => $this->statusKey(),
            'status_label' => $this->statusLabel(),
            'is_active' => $this->isPubliclyVisible(),
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
