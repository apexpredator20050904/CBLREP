<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Dedicated audit-trail model for administrative actions.
 *
 * Records every admin-side state change in the `audit_logs` table,
 * including the acting admin, IP address, user-agent, and a free-text
 * description of the action + its target.
 *
 * The static record() helper centralises logging so every controller
 * writes a consistent row without duplicating boilerplate.
 */
class AuditLog extends Model
{
    protected $table = 'audit_logs';

    protected $fillable = [
        'admin_id',
        'action',
        'target_type',
        'target_id',
        'details',
        'ip_address',
        'user_agent',
    ];

    protected $casts = [
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    public function admin()
    {
        return $this->belongsTo(User::class, 'admin_id');
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /**
     * Centralised helper — every controller should log via this method
     * so the audit trail is consistent and complete.
     *
     * @param  Request  $request     The incoming admin request (for IP / UA / user).
     * @param  string   $action      Human-readable action, e.g. "Verified member".
     * @param  string|null  $targetType  Model class or short name (user, resource, …).
     * @param  int|null  $targetId   Primary key of the affected record.
     * @param  string|null  $details  Optional free-text detail / reason.
     */
    public static function record(
        Request $request,
        string $action,
        ?string $targetType = null,
        ?int $targetId = null,
        ?string $details = null,
    ): self {
        return self::create([
            // Nullable on purpose: login endpoints log before Sanctum
            // has attached a user to the request (admin-login path).
            'admin_id'     => $request->user()?->id ?? $targetId,
            'action'       => $action,
            'target_type'  => $targetType,
            'target_id'    => $targetId,
            'details'      => $details,
            'ip_address'   => $request->ip(),
            'user_agent'   => $request->userAgent(),
        ]);
    }
}

