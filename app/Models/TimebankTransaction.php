<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TimebankTransaction extends Model
{
    const STATUS_PENDING = 'Pending';

    const STATUS_ACCEPTED = 'Accepted';

    const STATUS_IN_PROGRESS = 'In Progress';

    const STATUS_AWAITING_CONFIRMATION = 'Awaiting Confirmation';

    const STATUS_COMPLETED = 'Completed';

    const STATUS_CANCELLED = 'Cancelled';

    protected $fillable = [
        'service_id',
        'service_title',
        'provider_email',
        'provider_name',
        'requester_email',
        'requester_name',
        'barangay',
        'requested_hours',
        'hours_completed',
        'credits_transferred',
        'status',
        'confirmation_status',
        'completed_at',
    ];

    protected $casts = [
        'requested_hours' => 'float',
        'hours_completed' => 'float',
        'credits_transferred' => 'float',
        'completed_at' => 'datetime',
    ];

    /**
     * Shape expected by TransactionHistory.jsx / TimeBankContext.jsx
     * (created_at + completed_at are epoch-ms ints; fmtDate() does new Date(ts)).
     */
    public function toTransactionArray(): array
    {
        return [
            'transaction_id' => $this->id,
            'service_id' => $this->service_id,
            'service_title' => $this->service_title,
            'provider_email' => $this->provider_email,
            'provider_name' => $this->provider_name,
            'requester_email' => $this->requester_email,
            'requester_name' => $this->requester_name,
            'barangay' => $this->barangay ?? '',
            'requested_hours' => (float) $this->requested_hours,
            'hours_completed' => (float) $this->hours_completed,
            'credits_transferred' => (float) $this->credits_transferred,
            'status' => $this->status,
            'confirmation_status' => $this->confirmation_status,
            'created_at' => (int) ($this->created_at?->getTimestamp() ?? time()) * 1000,
            'completed_at' => $this->completed_at
                ? (int) $this->completed_at->getTimestamp() * 1000
                : null,
        ];
    }
}
