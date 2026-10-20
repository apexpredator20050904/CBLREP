<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * An FCM registration token belonging to a member's device.
 *
 * One member may have several (phone + tablet); one token maps to exactly one
 * member at a time, so a device handed to somebody else stops receiving the
 * previous owner's alerts.
 */
class DeviceToken extends Model
{
    protected $fillable = [
        'user_id',
        'token',
        'platform',
        // The versionCode (build number) the device is running, reported by the
        // app each time it registers. The server uses it to notify only the
        // members who are actually behind, instead of buzzing everybody.
        'build_number',
        'last_used_at',
    ];

    protected $casts = [
        'last_used_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
