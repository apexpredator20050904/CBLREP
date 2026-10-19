<?php

namespace App\Console\Commands;

use App\Services\AppUpdateNotifier;
use Illuminate\Console\Command;
use Throwable;

class NotifyAppUpdate extends Command
{
    protected $signature = 'app:notify-update
                            {--all : Announce to every member, not only the ones on an older build}
                            {--force : Re-send even if the members were already told about this release}';

    protected $description = 'Tell members that a new CBLREP build is available (push + inbox row)';

    public function handle(AppUpdateNotifier $notifier): int
    {
        $versionCode = (int) config('app_version.version_code');
        $versionName = (string) config('app_version.version_name');

        $this->info("Announcing CBLREP v{$versionName} (versionCode {$versionCode})");

        try {
            $result = $notifier->broadcast(
                all: (bool) $this->option('all'),
                force: (bool) $this->option('force'),
            );
        } catch (Throwable $error) {
            $this->error($error->getMessage());
            return self::FAILURE;
        }

        $this->newLine();
        $this->line("  members notified        : {$result['notified']}");
        $this->line("  audience (with a device): {$result['audience']}");

        if (! $this->option('all')) {
            $this->line("  already on this build   : {$result['skipped_up_to_date']}");
        }

        if ($result['notified'] === 0) {
            $this->newLine();
            $this->warn('Nobody was notified. Either every member is already on this build,');
            $this->warn('or they were told about this release before (use --force to re-send).');
        } else {
            $this->newLine();
            $this->info("Sent. Members on an older build will see the update prompt.");
        }

        return self::SUCCESS;
    }
}
