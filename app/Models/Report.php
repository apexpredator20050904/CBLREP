<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * A member's report about a malicious listing or account.
 *
 * The reportable is stored as a plain (`reportable_type`, `reportable_id`)
 * pair — `listing` or `user` — rather than an Eloquent morph, so the row
 * speaks the same vocabulary the mobile client does and no internal class
 * name is ever persisted. [subject()] resolves the pair back to a model.
 */
class Report extends Model
{
    /** The kinds of thing a member can report. */
    public const TARGET_LISTING = 'listing';

    public const TARGET_USER = 'user';

    public const TARGETS = [self::TARGET_LISTING, self::TARGET_USER];

    /** Why the member reported it. */
    public const REASON_SCAM = 'scam';

    public const REASON_INAPPROPRIATE = 'inappropriate_content';

    public const REASON_COUNTERFEIT = 'counterfeit';

    public const REASON_HARASSMENT = 'harassment';

    public const REASON_OTHER = 'other';

    public const REASONS = [
        self::REASON_SCAM,
        self::REASON_INAPPROPRIATE,
        self::REASON_COUNTERFEIT,
        self::REASON_HARASSMENT,
        self::REASON_OTHER,
    ];

    /** Where the report sits in the moderation lifecycle. */
    public const STATUS_PENDING = 'pending';

    public const STATUS_REVIEWED = 'reviewed';

    public const STATUS_ACTION_TAKEN = 'action_taken';

    public const STATUSES = [
        self::STATUS_PENDING,
        self::STATUS_REVIEWED,
        self::STATUS_ACTION_TAKEN,
    ];

    /**
     * How many distinct members must report a listing before the backend
     * pulls it out of the community feed for a moderator to look at.
     *
     * The listing is *flagged*, not removed: a moderator still decides what
     * happens to it. Three is deliberately high enough that a single grudge
     * cannot hide a neighbour's listing, and low enough that a genuine scam
     * does not keep collecting reports for days.
     */
    public const AUTO_FLAG_THRESHOLD = 3;

    protected $fillable = [
        'reporter_id',
        'reportable_type',
        'reportable_id',
        'reason',
        'description',
        'status',
        'reviewed_at',
        'reviewed_by',
        'resolution_note',
    ];

    protected $casts = [
        'reviewed_at' => 'datetime',
    ];

    // ------------------------------------------------------------------
    // Relations
    // ------------------------------------------------------------------

    /** The member who filed the report (null once their account is gone). */
    public function reporter()
    {
        return $this->belongsTo(User::class, 'reporter_id');
    }

    /** The moderator who last acted on the report. */
    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /**
     * The reported model, or null when it has since been deleted.
     *
     * @return Model|null
     */
    public function subject()
    {
        return match ($this->reportable_type) {
            self::TARGET_LISTING => Resource::find($this->reportable_id),
            self::TARGET_USER => User::find($this->reportable_id),
            default => null,
        };
    }

    /** A human label for the reported thing — the queue's "subject" column. */
    public function subjectLabel(): string
    {
        $subject = $this->subject();

        if ($subject instanceof Resource) {
            return 'Listing: '.$subject->title;
        }

        if ($subject instanceof User) {
            return 'Member: '.$subject->name;
        }

        return ucfirst((string) $this->reportable_type).' #'.$this->reportable_id.' (deleted)';
    }

    /**
     * Distinct pending reports against one target.
     *
     * Counted per REPORTER, not per row: the same member reporting the same
     * listing ten times is one signal, not ten.
     */
    public function scopePendingAgainst(Builder $query, string $type, int $id): Builder
    {
        return $query->where('reportable_type', $type)
            ->where('reportable_id', $id)
            ->where('status', self::STATUS_PENDING);
    }

    /** Human label for the reason, as shown to a moderator. */
    public function reasonLabel(): string
    {
        return match ($this->reason) {
            self::REASON_SCAM => 'Scam or fraud',
            self::REASON_INAPPROPRIATE => 'Inappropriate content',
            self::REASON_COUNTERFEIT => 'Counterfeit or fake item',
            self::REASON_HARASSMENT => 'Harassment or abuse',
            self::REASON_OTHER => 'Other',
            default => ucfirst((string) $this->reason),
        };
    }

    /** Human label for the moderation status. */
    public function statusLabel(): string
    {
        return match ($this->status) {
            self::STATUS_PENDING => 'Pending review',
            self::STATUS_REVIEWED => 'Reviewed',
            self::STATUS_ACTION_TAKEN => 'Action taken',
            default => ucfirst((string) $this->status),
        };
    }

    /** The wire shape consumed by the mobile app. */
    public function toArray(): array
    {
        return [
            'id' => $this->id,
            'reporter_id' => $this->reporter_id,
            'reportable_type' => $this->reportable_type,
            'reportable_id' => $this->reportable_id,
            'reason' => $this->reason,
            'reason_label' => $this->reasonLabel(),
            'description' => $this->description,
            'status' => $this->status,
            'status_label' => $this->statusLabel(),
            'subject_label' => $this->subjectLabel(),
            'created_at' => $this->created_at?->toIso8601String(),
            'reviewed_at' => $this->reviewed_at?->toIso8601String(),
        ];
    }
}
