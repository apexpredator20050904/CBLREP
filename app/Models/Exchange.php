<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * A direct barter proposal between two members.
 *
 * The platform previously supported freecycling (one-way gifting) and
 * temporary lending (borrow + return). Both are gone; only item-for-item and
 * skill-for-skill trades remain. A barter is a two-way proposal:
 *
 *   provider  → the member who owns the wanted listing
 *   receiver  → the proposer, who names what they give in return
 *
 * The "offered in return" side lives in `offered_resource_id` /
 * `offered_item`. Those columns are what make a one-sided gift structurally
 * unrepresentable — there is no way to record a transfer that gives nothing
 * back.
 */
class Exchange extends Model
{
    public const TYPE_BARTER = 'barter';

    /** The only live exchange type. Everything else was retired. */
    public const TYPES = [self::TYPE_BARTER];

    /**
     * Types this system used to support, kept only so a stale client gets a
     * specific "no longer supported" error instead of a generic validation
     * failure. Never write these to the column.
     */
    public const RETIRED_TYPES = ['freecycling', 'lending'];

    public const STATUS_PENDING = 'pending';
    public const STATUS_ACCEPTED = 'accepted';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_CANCELLED = 'cancelled';

    /**
     * Status adjacency list — current status => statuses reachable from it.
     *
     * Declared as an adjacency list rather than a flat list so an illegal jump
     * (pending → completed) is impossible to express. Terminal states map to an
     * empty array, which makes them absorbing by construction.
     */
    public const TRANSITIONS = [
        self::STATUS_PENDING => [self::STATUS_ACCEPTED, self::STATUS_REJECTED, self::STATUS_CANCELLED],
        self::STATUS_ACCEPTED => [self::STATUS_COMPLETED, self::STATUS_CANCELLED],
        self::STATUS_COMPLETED => [],
        self::STATUS_REJECTED => [],
        self::STATUS_CANCELLED => [],
    ];

    protected $fillable = [
        'resource_id',
        'offered_resource_id',
        'offered_item',
        'provider_id',
        'receiver_id',
        'exchange_type',
        'status',
        'barangay',
        'purok_sitio',
        'proposer_confirmed',
        'owner_confirmed',
        'proposer_confirmed_at',
        'owner_confirmed_at',
    ];

    protected $casts = [
        'status' => 'string',
        'proposer_confirmed' => 'boolean',
        'owner_confirmed' => 'boolean',
        'proposer_confirmed_at' => 'datetime',
        'owner_confirmed_at' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    /** The listing being requested — owned by the provider. */
    public function resource()
    {
        return $this->belongsTo(Resource::class);
    }

    /** The proposer's own listing, offered in return. Null for skill trades. */
    public function offeredResource()
    {
        return $this->belongsTo(Resource::class, 'offered_resource_id');
    }

    /** Owner of the requested listing — the party who answers the proposal. */
    public function provider()
    {
        return $this->belongsTo(User::class, 'provider_id');
    }

    /** The proposer — the member asking to trade. */
    public function receiver()
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    // ------------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------------

    /** Can this barter legally move to $status? */
    public function canTransitionTo(string $status): bool
    {
        return in_array($status, self::TRANSITIONS[$this->status] ?? [], true);
    }

    public function isTerminal(): bool
    {
        return empty(self::TRANSITIONS[$this->status] ?? null);
    }

    // ------------------------------------------------------------------
    // Dual-confirmation (both parties must confirm the handover)
    // ------------------------------------------------------------------

    /**
     * True when the given member already recorded their half of the
     * dual confirmation for this exchange.
     */
    public function hasConfirmed(int $userId): bool
    {
        if ($userId === $this->receiver_id) {
            return (bool) $this->proposer_confirmed;
        }
        if ($userId === $this->provider_id) {
            return (bool) $this->owner_confirmed;
        }

        return false;
    }

    /** Both halves recorded — the row may be promoted to completed. */
    public function isDualConfirmed(): bool
    {
        return (bool) $this->proposer_confirmed && (bool) $this->owner_confirmed;
    }

    /** Human-readable progress label for admin + mobile UI. */
    public function confirmationLabel(): string
    {
        if ($this->isDualConfirmed()) {
            return 'Both confirmed — Exchange completed';
        }
        if ($this->proposer_confirmed || $this->owner_confirmed) {
            return "Waiting for other party's confirmation";
        }

        return 'Awaiting both confirmations';
    }

    // ------------------------------------------------------------------
    // Presentation helpers (admin console + mobile app)
    // ------------------------------------------------------------------

    /** Single type — kept so existing label/filter plumbing keeps working. */
    public function frontendType(): string
    {
        return 'Bartering';
    }

    public function frontendStatus(): string
    {
        return match ($this->status) {
            self::STATUS_PENDING => 'Pending',
            self::STATUS_ACCEPTED => 'Accepted',
            self::STATUS_COMPLETED => 'Completed',
            self::STATUS_REJECTED => 'Declined',
            self::STATUS_CANCELLED => 'Cancelled',
            default => ucfirst((string) $this->status),
        };
    }

    /**
     * What the proposer puts up in return, as one display string.
     * Falls back to a neutral label rather than null so the table cell is
     * never blank — a missing offer is a data-integrity question, and an
     * empty cell would hide it.
     */
    public function offeredLabel(): string
    {
        return $this->offeredResource?->title
            ?: ($this->offered_item ?: 'Skill / service offered');
    }

    /** What the provider is offering — the listing being requested. */
    public function requestedLabel(): string
    {
        return $this->resource?->title ?? 'Listing removed';
    }
}
