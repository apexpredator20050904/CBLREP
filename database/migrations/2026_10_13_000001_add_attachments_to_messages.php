<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            // Messenger-style attachments stored on the `public` disk under
            // `chat_attachments/`. Nullable so existing text-only rows stay valid.
            if (! Schema::hasColumn('messages', 'file_path')) {
                $table->string('file_path')->nullable()->after('body');
            }
            if (! Schema::hasColumn('messages', 'file_type')) {
                // `image` | `document` — drives bubble rendering on mobile.
                $table->string('file_type', 20)->nullable()->after('file_path');
            }
            if (! Schema::hasColumn('messages', 'file_name')) {
                $table->string('file_name')->nullable()->after('file_type');
            }
            if (! Schema::hasColumn('messages', 'file_size')) {
                $table->unsignedBigInteger('file_size')->nullable()->after('file_name');
            }
            if (! Schema::hasColumn('messages', 'mime_type')) {
                $table->string('mime_type', 100)->nullable()->after('file_size');
            }
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropColumn(['file_path', 'file_type', 'file_name', 'file_size', 'mime_type']);
        });
    }
};
