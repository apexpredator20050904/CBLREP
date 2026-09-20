<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Exchange extends Model
{
    public const TYPE_LENDING = 'lending';
    public const TYPE_BARTER = 'barter';
    public const TYPE_FREECYCLE = 'freecycle';
    public const TYPE_TIME_BANKING = 'time_banking';

    protected $fillable = [
        'resource_id',
        'provider_id',
        'receiver_id',
        'exchange_type',
        'status',
        'scheduled_return_date',
        'credits_exchanged',
    ];

    protected $casts = [
        'scheduled_return_date' => 'date',
        'credits_exchanged' => 'float',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function resource()
    {
        return $this->belongsTo(Resource::class);
    }

    public function provider()
    {
        return $this->belongsTo(User::class, 'provider_id');
    }

    public function receiver()
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    // ------------------------------------------------------------------
    // Frontend labels (tabs on ExchangesPage / admin pages)
    // ------------------------------------------------------------------

    public function frontendType(): string
    {
        return match ($this->exchange_type) {
            self::TYPE_FREECYCLE => 'Freecycling',
            self::TYPE_BARTER => 'Bartering',
            self::TYPE_TIME_BANKING => 'Time Banking',
            default => 'Lending',
        };
    }

    public function frontendStatus(): string
    {
        return match ($this->status) {
            'pending' => 'Pending',
            'accepted' => 'Active',
            'completed' => 'Completed',
            'cancelled' => 'Cancelled',
            default => ucfirst((string) $this->status),
        };
    }
}
