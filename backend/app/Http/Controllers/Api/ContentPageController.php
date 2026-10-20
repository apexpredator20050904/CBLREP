<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ContentPage;
use Illuminate\Http\Request;

/**
 * Public, unauthenticated content-page reader.
 *
 * Serves published municipal pages created from the admin console
 * (/admin/content). Drafts are never exposed: every query filters on
 * status = published AND published_at IS NOT NULL, so an unknown slug and
 * an unpublished slug are indistinguishable (both 404).
 *
 * Consumed by the React public route /page/:slug (frontend/src/pages/
 * PublicPage.jsx) and by the mobile app via the same JSON endpoint.
 */
class ContentPageController extends Controller
{
    /** GET /api/pages — catalogue of published pages (slug + title only). */
    public function index(Request $request)
    {
        $pages = ContentPage::query()
            ->where('status', 'published')
            ->whereNotNull('published_at')
            ->orderBy('published_at', 'desc')
            ->get(['id', 'slug', 'title']);

        return response()->json(['pages' => $pages]);
    }

    /** GET /api/page/{slug} — the full published page. */
    public function show(Request $request, $slug)
    {
        $page = ContentPage::query()
            ->where('status', 'published')
            ->whereNotNull('published_at')
            ->where('slug', $slug)
            ->firstOrFail();

        return response()->json([
            'page' => [
                'id'           => $page->id,
                'title'        => $page->title,
                'slug'         => $page->slug,
                'body'         => $page->body,
                'published_at' => $page->published_at?->toIso8601String(),
                'updated_at'   => $page->updated_at?->toIso8601String(),
            ],
        ]);
    }
}