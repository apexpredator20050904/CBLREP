<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Mail\Message;
use Illuminate\Support\Facades\Mail;
use Throwable;

class MailTestCommand extends Command
{
    protected $signature = 'mail:test {email : Recipient address for the test message}';

    protected $description = 'Send a test message using the configured mail transport';

    public function handle(): int
    {
        $email = (string) $this->argument('email');
        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            $this->error('Please provide a valid recipient e-mail address.');

            return self::INVALID;
        }

        try {
            Mail::raw('This is a test message from CBLREP at '.now()->toDateTimeString().'.', function (Message $message) use ($email) {
                $message->to($email)->subject('CBLREP mail configuration test');
            });
        } catch (Throwable $exception) {
            $this->error('Could not send test e-mail: '.$exception->getMessage());

            return self::FAILURE;
        }

        $this->info("Test e-mail sent successfully to {$email}.");

        return self::SUCCESS;
    }
}
