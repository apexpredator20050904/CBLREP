<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Announcement;
use App\Models\AuditLog;
use App\Models\ContentPage;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Content + Notifications admin endpoints (Trinidad municipal console).
 * Consumed by React pages /admin/content and /admin/notifications.
 * Every handler re-checks the admin role via guard().
 */
class ContentAdminController extends Controller
{
    private function guard(Request $request): void
    {
        abort_unless($request->user()?->role === 'admin', 403, 'Unauthorized. Admin access required.');
    }

    private function log(Request $request, string $action, ?string $t, ?int $id, ?string $d = null): void
    {
        AuditLog::record($request, $action, $t, $id, $d);
    }

    // ---------------- Content management (/admin/content) ----------------

    /** GET /admin/content — summary { total, published, drafts } + rows. */
    public function contentIndex(Request $request)
    {
        $this->guard($request);
        $pages = ContentPage::with('author:id,name')->latest()->get();
        return response()->json([
            'summary' => [
                'total' => $pages->count(),
                'published' => $pages->where('status', 'published')->count(),
                'drafts' => $pages->where('status', 'draft')->count(),
            ],
            'pages' => $pages->map(fn (ContentPage $p) => [
                'id' => $p->id,
                'title' => $p->title,
                'slug' => $p->slug,
                'status' => $p->status,
                'author' => $p->author?->name,
                'published_at' => $p->published_at?->format('M j, Y'),
                'updated_at' => $p->updated_at?->format('M j, Y g:i A'),
            ])->values(),
        ]);
    }

    /** POST /admin/content — create a draft or publish directly. */
    public function contentStore(Request $request)
    {
        $this->guard($request);
        $v = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'slug' => ['nullable', 'string', 'max:255', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', 'unique:content_pages,slug'],
            'body' => ['nullable', 'string'],
            'status' => ['nullable', 'in:draft,published'],
        ]);
        $slug = $v['slug'] ?? Str::slug($v['title']);
        $base = $slug;
        $i = 2;
        while (ContentPage::where('slug', $slug)->exists()) {
            $slug = "{$base}-{$i}";
            $i++;
        }
        $status = $v['status'] ?? 'draft';
        $page = ContentPage::create([
            'title' => $v['title'],
            'slug' => $slug,
            'body' => $v['body'] ?? null,
            'status' => $status,
            'created_by' => $request->user()->id,
            'published_at' => $status === 'published' ? now() : null,
        ]);
        $this->log($request, "Created content page \"{$page->title}\" ({$page->status})", 'content_page', $page->id);
        return response()->json(['message' => 'Page saved.', 'page' => $page->fresh()], 201);
    }

    /** PATCH /admin/content/{id} — edit or publish/unpublish. */
    public function contentUpdate(Request $request, $id)
    {
        $this->guard($request);
        $page = ContentPage::findOrFail($id);
        $v = $request->validate([
            'title' => ['sometimes', 'string', 'max:255'],
            'slug' => ['sometimes', 'string', 'max:255', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', "unique:content_pages,slug,{$page->id}"],
            'body' => ['sometimes', 'nullable', 'string'],
            'status' => ['sometimes', 'in:draft,published'],
        ]);
        $page->fill($v);
        if (($v['status'] ?? null) === 'published' && ! $page->published_at) {
            $page->published_at = now();
        }
        if (($v['status'] ?? null) === 'draft') {
            $page->published_at = null;
        }
        $page->save();
        $this->log($request, "Updated content page \"{$page->title}\" ({$page->status})", 'content_page', $page->id);
        return response()->json(['message' => 'Page updated.', 'page' => $page->fresh()]);
    }

    /** DELETE /admin/content/{id} — remove an outdated page. */
    public function contentDestroy(Request $request, $id)
    {
        $this->guard($request);
        $page = ContentPage::findOrFail($id);
        $title = $page->title;
        $page->delete();
        $this->log($request, "Deleted content page \"{$title}\"", 'content_page', (int) $id);

        return response()->json(['message' => 'Page deleted.']);
    }

    public function notifIndex(Request $request)
    {
        $this->guard($request);
        $items = Announcement::with('author:id,name')->latest()->get();
        return response()->json([
            'summary' => [
                'total' => $items->count(),
                'sent' => $items->where('status', 'sent')->count(),
                'scheduled' => $items->where('status', 'scheduled')->count(),
                'drafts' => $items->where('status', 'draft')->count(),
            ],
            'announcements' => $items->map(fn (Announcement $item) => [
                'id' => $item->id, 'title' => $item->title, 'audience' => $item->audience,
                'barangay' => $item->barangay, 'status' => $item->status,
                'scheduled_at' => $item->scheduled_at?->format('M j, Y g:i A'),
                'sent_at' => $item->sent_at?->format('M j, Y g:i A'),
                'updated_at' => $item->updated_at?->format('M j, Y g:i A'),
            ])->values(),
        ]);
    }

    public function notifStore(Request $request)
    {
        $this->guard($request);
        $v = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'body' => ['required', 'string'],
            'audience' => ['required', 'in:all,verified,barangay,admins'],
            'barangay' => ['nullable', 'string', 'max:100', 'required_if:audience,barangay'],
            'status' => ['nullable', 'in:draft,scheduled,sent'],
            'scheduled_at' => ['nullable', 'date', 'required_if:status,scheduled'],
        ]);
        $status = $v['status'] ?? 'draft';
        $item = Announcement::create([
            'title' => $v['title'], 'body' => $v['body'], 'audience' => $v['audience'],
            'barangay' => $v['audience'] === 'barangay' ? ($v['barangay'] ?? null) : null,
            'status' => $status, 'scheduled_at' => $status === 'scheduled' ? $v['scheduled_at'] : null,
            'sent_at' => $status === 'sent' ? now() : null, 'created_by' => $request->user()->id,
        ]);
        $this->log($request, "Created announcement \"{$item->title}\" ({$item->status})", 'announcement', $item->id);
        return response()->json(['message' => 'Announcement saved.', 'announcement' => $item], 201);
    }

    public function notifSend(Request $request, $id)
    {
        $this->guard($request);
        $item = Announcement::findOrFail($id);
        $item->update(['status' => 'sent', 'sent_at' => now(), 'scheduled_at' => null]);
        $this->log($request, "Sent announcement \"{$item->title}\"", 'announcement', $item->id);
        return response()->json(['message' => 'Announcement sent.', 'announcement' => $item->fresh()]);
    }

    public function notifDestroy(Request $request, $id)
    {
        $this->guard($request);
        $item = Announcement::findOrFail($id);
        $title = $item->title;
        $item->delete();
        $this->log($request, "Deleted announcement \"{$title}\"", 'announcement', (int) $id);
        return response()->json(['message' => 'Announcement deleted.']);
    }
}
