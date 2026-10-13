<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MemberNotification extends Model
{
    protected $fillable = [
        'user_id',
        'announcement_id',
        'type',
        'title',
        'body',
        'data',
        'read_at',
    ];

    protected $casts = ['data' => 'array', 'read_at' => 'datetime'];

    public function user() { return $this->belongsTo(User::class); }
    public function announcement() { return $this->belongsTo(Announcement::class); }
}
