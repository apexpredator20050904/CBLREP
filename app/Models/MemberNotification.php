<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MemberNotification extends Model
{
    protected $fillable = [
        'user_id',
        'announcement_id',
        'type',
        // The release an "a new version is available" row refers to. It is the
        // dedup key for that notification type, so re-announcing the same
        // release never records the row twice.
        'app_version_code',
        'title',
        'body',
        'data',
        'read_at',
    ];

    protected $casts = ['data' => 'array', 'read_at' => 'datetime'];

    public function user() { return $this->belongsTo(User::class); }
    public function announcement() { return $this->belongsTo(Announcement::class); }
}
