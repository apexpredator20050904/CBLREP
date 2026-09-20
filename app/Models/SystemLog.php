<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Admin action audit trail. The dedicated AuditLog model also reads this
 * table (system_logs) until a separate audit table exists.
 */
class SystemLog extends Model
{
    protected $fillable = [
        'admin_id',
        'action',
        'target_type',
        'target_id',
    ];

    public function admin()
    {
        return $this->belongsTo(User::class, 'admin_id');
    }
}
