<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BarterProposal extends Model
{
    public const STATUS_PENDING = 'pending';
    public const STATUS_ACCEPTED = 'accepted';
    public const STATUS_REJECTED = 'rejected';
    public const STATUS_COMPLETED = 'completed';

    public const STATUSES = [
        self::STATUS_PENDING,
        self::STATUS_ACCEPTED,
        self::STATUS_REJECTED,
        self::STATUS_COMPLETED,
    ];

    protected $fillable = [
        'sender_id',
        'receiver_id',
        'offered_item_id',
        'requested_item_id',
        'status',
    ];

    public function sender()
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function receiver()
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    public function offeredItem()
    {
        return $this->belongsTo(Resource::class, 'offered_item_id');
    }

    public function requestedItem()
    {
        return $this->belongsTo(Resource::class, 'requested_item_id');
    }

    /** Human-facing label for UI badges. */
    public function statusLabel(): string
    {
        return match ($this->status) {
            self::STATUS_ACCEPTED => 'Accepted',
            self::STATUS_REJECTED => 'Rejected',
            self::STATUS_COMPLETED => 'Completed',
            default => 'Pending',
        };
    }
}
