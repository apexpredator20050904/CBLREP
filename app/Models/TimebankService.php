<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TimebankService extends Model
{
    protected $fillable = [
        'provider_email',
        'provider_name',
        'title',
        'description',
        'category',
        'estimated_hours',
        'location',
        'availability',
        'status',
    ];

    protected $casts = [
        'estimated_hours' => 'float',
    ];

    /**
     * Shape expected by src/timebank/* components (created_at is an epoch-ms int).
     */
    public function toServiceArray(): array
    {
        return [
            'service_id' => $this->id,
            'provider_email' => $this->provider_email,
            'provider_name' => $this->provider_name,
            'title' => $this->title,
            'description' => $this->description ?? '',
            'category' => $this->category ?? 'Skills',
            'estimated_hours' => (float) $this->estimated_hours,
            'location' => $this->location ?? '',
            'availability' => $this->availability ?? '',
            'status' => $this->status ?? 'open',
            'created_at' => (int) ($this->created_at?->getTimestamp() ?? time()) * 1000,
        ];
    }
}
