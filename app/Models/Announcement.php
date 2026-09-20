<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Admin announcement / notification broadcast.
 *
 * Composed by municipal admins and targeted at a user segment:
 *   all       — every registered member
 *   verified  — verified Trinidad residents only
 *   barangay  — verified residents of one Trinidad barangay (+ barangay)
 *   admins    — admin staff only
 *
 * Lifecycle: draft -> scheduled (scheduled_at set) -> sent (sent_at set).
 * Actual push delivery is handled by the Flutter client polling
 * GET /announcements; the admin panel only manages the records here.
 */
class Announcement extends Model
{
    protected $fillable = [
        'title',
        'body',
        'audience',
        'barangay',
        'status',
        'scheduled_at',
        'sent_at',
        'created_by',
    ];

    protected $casts = [
        'scheduled_at' => 'datetime',
        'sent_at' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function author()
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
