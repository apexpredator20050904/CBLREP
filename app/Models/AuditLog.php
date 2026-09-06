<?php

namespace App\Models;

/**
 * Admin recent actions use system_logs until a dedicated audit table exists.
 */
class AuditLog extends SystemLog
{
    protected $table = 'system_logs';
}
