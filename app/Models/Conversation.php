<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Conversation extends Model
{
    protected $fillable = [
        'listing_id',
        'buyer_id',
        'seller_id',
        'participant_one_id',
        'participant_two_id',
        'last_message_at',
    ];

    protected $casts = ['last_message_at' => 'datetime'];

    public function participantOne() { return $this->belongsTo(User::class, 'participant_one_id'); }
    public function participantTwo() { return $this->belongsTo(User::class, 'participant_two_id'); }
    public function messages() { return $this->hasMany(Message::class); }

    /** The listing this inquiry is about (null for plain member-to-member). */
    public function listing() { return $this->belongsTo(Resource::class, 'listing_id'); }

    /** The member who opened the inquiry. */
    public function buyer() { return $this->belongsTo(User::class, 'buyer_id'); }

    /** The listing owner being inquired with. */
    public function seller() { return $this->belongsTo(User::class, 'seller_id'); }

    public function includesUser(int $userId): bool
    {
        return $this->participant_one_id === $userId || $this->participant_two_id === $userId;
    }

    public function otherParticipant(int $userId): ?User
    {
        return $this->participant_one_id === $userId ? $this->participantTwo : $this->participantOne;
    }

    public static function between(int $firstUserId, int $secondUserId): self
    {
        [$one, $two] = $firstUserId < $secondUserId
            ? [$firstUserId, $secondUserId]
            : [$secondUserId, $firstUserId];

        return self::firstOrCreate(
            [
                'participant_one_id' => $one,
                'participant_two_id' => $two,
                'listing_id' => null,
            ],
        );
    }

    /**
     * Find or open the single inquiry thread for a listing between its owner
     * and one interested member. Keyed on (listing, buyer, seller) so the same
     * pair always resumes the same conversation about the same post, while a
     * member inquiring about two different listings gets two threads.
     */
    public static function forListing(int $listingId, int $buyerId, int $sellerId): self
    {
        [$one, $two] = $buyerId < $sellerId
            ? [$buyerId, $sellerId]
            : [$sellerId, $buyerId];

        return self::firstOrCreate(
            [
                'listing_id' => $listingId,
                'buyer_id' => $buyerId,
                'seller_id' => $sellerId,
            ],
            [
                'participant_one_id' => $one,
                'participant_two_id' => $two,
            ],
        );
    }
}
