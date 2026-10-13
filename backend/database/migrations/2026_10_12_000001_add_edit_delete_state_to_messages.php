<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            // Editing a sent message is allowed, but the original text is
            // lost, so `edited_at` records that the body changed after the
            // fact (Messenger-style "edited" marker in the bubble).
            if (! Schema::hasColumn('messages', 'edited_at')) {
                $table->timestamp('edited_at')->nullable()->after('body');
            }
            // Soft delete: a removed message disappears from both chat
            // participants but stays in the table, because messages back the
            // admin inquiry oversight and report totals. Hard-deleting them
            // would erase an official record.
            if (! Schema::hasColumn('messages', 'deleted_at')) {
                $table->timestamp('deleted_at')->nullable()->after('edited_at');
                // The thread read is always "live rows for this conversation,
                // newest first", so index the pair with the tombstone.
                $table->index(['conversation_id', 'deleted_at'], 'messages_conversation_visible_index');
            }
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            if (Schema::hasIndex('messages', 'messages_conversation_visible_index')) {
                $table->dropIndex('messages_conversation_visible_index');
            }
            $table->dropColumn(['edited_at', 'deleted_at']);
        });
    }
};
