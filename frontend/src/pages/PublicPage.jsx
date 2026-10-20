import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { api } from "../services/adminApi";

// ─────────────────────────────────────────────────────────────
// Public reader for published content pages — /page/:slug
// ─────────────────────────────────────────────────────────────
// Anonymous counterpart to the admin Content management screens: fetches
// GET /api/page/{slug} (backend routes/web.php) and renders the HTML body.
// Drafts and unknown slugs return 404 from the API and render the
// "Page not found" state below.
export default function PublicPage() {
  const { slug } = useParams();
  // The result is stored together with the slug that produced it, so a
  // newly navigated slug reads as "loading" without any synchronous
  // setState() inside the effect (react-hooks/set-state-in-effect).
  const [result, setResult] = useState(null);   // { slug, page }
  const [failure, setFailure] = useState(null); // { slug }

  useEffect(() => {
    let mounted = true;
    if (!slug) return undefined;
    api
      .get(`/page/${slug}`)
      .then((res) => { if (mounted) setResult({ slug, page: res.data.page }); })
      .catch(() => { if (mounted) setFailure({ slug }); });
    return () => { mounted = false; };
  }, [slug]);

  const failed = failure?.slug === slug;
  const pending = !failed && (!result || result.slug !== slug);

  if (pending) {
    return <p className="p-6 text-sm text-stone-500">Loading page…</p>;
  }

  if (failed) {
    return (
      <main className="grid min-h-[60vh] place-items-center p-8 text-center">
        <div>
          <h1 className="text-2xl font-extrabold text-emerald-950">Page not found</h1>
          <p className="mt-2 text-sm text-stone-600">
            That page doesn’t exist, isn’t published yet, or the server couldn’t be reached.
          </p>
          <Link to="/login" className="mt-4 inline-block text-emerald-700 underline">
            ← Back to sign in
          </Link>
        </div>
      </main>
    );
  }

  const page = result.page;

  return (
    <main className="mx-auto max-w-3xl px-4 py-10">
      <article>
        <h1 className="text-3xl font-extrabold text-emerald-950">{page.title}</h1>
        {page.published_at && (
          <p className="mt-1 text-xs text-stone-500">
            Published {new Date(page.published_at).toLocaleDateString()}
          </p>
        )}
        {/* Body is authored as HTML in the admin textarea (stored as text). */}
        <div
          className="mt-6 space-y-3 text-stone-800 [&_h2]:text-xl [&_h2]:font-bold [&_h2]:text-emerald-950 [&_li]:mt-1 [&_ul]:list-disc [&_ul]:pl-6"
          dangerouslySetInnerHTML={{ __html: page.body || "" }}
        />
      </article>
    </main>
  );
}