<?php

namespace Tests\Feature;

use App\Models\User;
use App\Notifications\ResetPasswordCode;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Notification;
use RuntimeException;
use Tests\TestCase;

class MailTestCommandTest extends TestCase
{
    public function test_mail_test_command_sends_a_test_message(): void
    {
        Mail::shouldReceive('raw')->once();

        $this->artisan('mail:test', ['email' => 'recipient@example.test'])
            ->expectsOutput('Test e-mail sent successfully to recipient@example.test.')
            ->assertExitCode(0);
    }

    public function test_mail_test_command_reports_transport_errors(): void
    {
        Mail::shouldReceive('raw')
            ->once()
            ->andThrow(new RuntimeException('SMTP connection refused'));

        $this->artisan('mail:test', ['email' => 'recipient@example.test'])
            ->expectsOutput('Could not send test e-mail: SMTP connection refused')
            ->assertExitCode(1);
    }

    public function test_reset_code_notification_is_queueable(): void
    {
        $this->assertInstanceOf(ShouldQueue::class, new ResetPasswordCode('123456'));
    }

    public function test_forgot_password_returns_a_clean_error_if_mail_fails(): void
    {
        $user = User::create([
            'name' => 'Mail Test Member',
            'email' => uniqid('mail-test-').'@example.test',
            'password' => bcrypt('secret1234'),
            'role' => User::ROLE_USER,
        ]);

        Notification::shouldReceive('sendNow')
            ->once()
            ->andThrow(new RuntimeException('SMTP unavailable'));

        $this->postJson('/api/forgot-password', ['email' => $user->email])
            ->assertStatus(503)
            ->assertExactJson([
                'message' => 'We could not send the reset e-mail right now. Please try again shortly.',
            ]);

        $this->assertDatabaseMissing('password_reset_tokens', ['email' => $user->email]);
    }
}
