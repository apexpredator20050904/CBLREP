<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Persistent message records (totals for admin reports). Live chat delivery
 * itself lives in the `messages` table — see ConversationController.
 *
 * A member may edit or delete their own message. Deletion is SOFT
 * (`deleted_at`) rather than a row removal: messages are the evidence behind
 * the admin inquiry oversight and report totals, so a removed message must
 * still exist server-side while disappearing from both chat participants.
 *
 * SoftDeletes supplies both the `deleted_at` handling and the default scope
 * that hides removed rows, so no extra global scope is registered here.
 */
class Message extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'conversation_id',
        'sender_id',
        'recipient_email',
        'body',
        'read_at',
        'edited_at',
        'file_path',
        'file_type',
        'file_name',
        'file_size',
        'mime_type',
    ];

    protected $casts = [
        'read_at' => 'datetime',
        'edited_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    public function sender()
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }

    public function isEdited(): bool
    {
        return $this->edited_at !== null;
    }

    public function isDeleted(): bool
    {
        return $this->deleted_at !== null;
    }

    /** Shape consumed by the Flutter chat screen and the admin console. */
    public function toChatPayload(): array
    {
        $fileUrl = $this->file_path
            ? url('storage/'.$this->file_path)
            : null;

        return [
            'id' => $this->id,
            'body' => (string) $this->body,
            'sender_id' => $this->sender_id,
            'sender' => $this->sender?->only(['id', 'name', 'email']),
            'edited_at' => $this->edited_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
            'read_at' => $this->read_at?->toISOString(),
            'file_path' => $this->file_path,
            'file_url' => $fileUrl,
            'file_type' => $this->file_type,
            'file_name' => $this->file_name,
            'file_size' => $this->file_size !== null ? (int) $this->file_size : null,
            'mime_type' => $this->mime_type,
        ];
    }

    public function hasAttachment(): bool
    {
        return $this->file_path !== null && $this->file_path !== '';
    }

    public function isImage(): bool
    {
        return $this->file_type === 'image';
    }

    public function isVideo(): bool
    {
        return $this->file_type === 'video';
    }
}