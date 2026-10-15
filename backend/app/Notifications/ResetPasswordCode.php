<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

/**
 * Mailed 6-digit password reset code used by the mobile "Forgot password"
 * flow. Deliberately short-lived and single-use (the controller deletes the
 * row from password_reset_tokens as soon as it is redeemed).
 */
class ResetPasswordCode extends Notification
{
    use Queueable;

    public function __construct(
        public string $code,
        public string $memberName = '',
        public int $ttlMinutes = 15,
    ) {
    }

    /**
     * Mail only — the mobile client polls nothing, so no database channel.
     *
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $greeting = trim($this->memberName) !== '' ? trim($this->memberName) : 'neighbour';

        return (new MailMessage)
            ->subject('CBLREP password reset code')
            ->greeting("Hello {$greeting},")
            ->line('Use this code to set a new password for your Community-Based Local Resources Exchange Portal account:')
            ->line("**{$this->code}**")
            ->line("The code expires in {$this->ttlMinutes} minutes and can only be used once.")
            ->line('If you did not request a password reset you can safely ignore this e-mail.')
            ->salutation('— CBLREP · Trinidad, Bohol');
    }
}
