<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Persistent message records (totals for admin reports). Live chat delivery
 * itself lives in storage/app/realtime.json — see RealtimeController.
 */
class Message extends Model
{
    protected $fillable = [
        'sender_id',
        'recipient_email',
        'body',
        'read_at',
    ];

    protected $casts = [
        'read_at' => 'datetime',
    ];

    public function sender()
    {
        return $this->belongsTo(User::class, 'sender_id');
    }
}
