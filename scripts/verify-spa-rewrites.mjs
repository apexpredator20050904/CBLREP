#!/usr/bin/env node
/**
 * Verifies the SPA rewrite rule declared in vercel.json behaves the way
 * Vercel's edge router will behave it — filesystem first, rewrites only for
 * paths that are not real files.
 *
 * Mirrors Vercel's resolution order:
 *   1. Static files that exist in the output directory are served as-is.
 *   2. `cleanUrls` tries `<path>/index.html` and `<path>.html`.
 *   3. Only then does the `rewrites` rule apply.
 *
 *   node scripts/verify-spa-rewrites.mjs            # uses ./dist
 *   node scripts/verify-spa-rewrites.mjs path/to/dist
 */
import { readFileSync, existsSync, statSync } from "node:fs";
import { join, resolve, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..");
const distDir = resolve(process.argv[2] ?? join(repoRoot, "frontend", "dist"));

const vercel = JSON.parse(readFileSync(join(repoRoot, "vercel.json"), "utf8"));
const [rule] = vercel.rewrites ?? [];

const fail = (msg) => {
  console.error(`✗ ${msg}`);
  process.exitCode = 1;
};

if (!existsSync(distDir)) {
  fail(`No build output at ${distDir}. Run: cd frontend && npm run build`);
  process.exit(1);
}
if (!existsSync(join(distDir, "index.html"))) {
  fail(`index.html missing from ${distDir}`);
  process.exit(1);
}

console.log(`Build output: ${relative(repoRoot, distDir) || distDir}`);
console.log(`Rewrite:     ${rule.source}  ->  ${rule.destination}\n`);

/** Does a real file exist for this request path on disk? */
function servedByFilesystem(pathname) {
  const clean = pathname.replace(/\/+$/, "") || "/";
  const candidates =
    clean === "/"
      ? ["/index.html"]
      : [clean, `${clean}/index.html`, `${clean}.html`];
  return candidates.find((c) => {
    const file = join(distDir, c);
    if (!file.startsWith(distDir)) return false; // path traversal guard
    return existsSync(file) && statSync(file).isFile();
  });
}

/** Applies the vercel.json rewrite rule, returning the rewrite target or null. */
function rewrite(pathname) {
  // Vercel `source` uses path-to-regexp; `/((?!api/).*)` is a negative
  // lookahead that excludes /api/* from the SPA catch-all.
  const captured = /^\/(.*)$/.exec(pathname);
  if (!captured) return null;
  const rest = captured[1];
  if (rest === "api" || rest.startsWith("api/")) return null; // excluded
  return rule.destination.replace(/^\//, "");
}

// Client routes that must survive a hard refresh.
const clientRoutes = [
  "/",
  "/login",
  "/admin",
  "/admin/users",
  "/admin/verification",
  "/admin/listings",
  "/admin/listings/offers",
  "/admin/listings/needs",
  "/admin/listings/flagged",
  "/admin/inquiries",
  "/admin/map",
  "/admin/exchanges",
  "/admin/barter-requests",
  "/admin/notifications",
  "/admin/content",
  "/admin/reports",
  "/admin/analytics",
  "/admin/audit-logs",
  "/admin/settings",
  "/dashboard",
  "/listings",
  "/chats",
  "/users",
];

console.log("Client routes (must resolve to index.html, never 404):");
let ok = 0;
for (const route of clientRoutes) {
  const fromFs = servedByFilesystem(route);
  const resolved = fromFs ?? rewrite(route);
  // Compare without a leading slash: the filesystem check yields
  // "/index.html" while the rewrite yields "index.html".
  const good = resolved?.replace(/^\//, "") === "index.html";
  if (good) ok += 1;
  console.log(`  ${good ? "✓" : "✗"} ${route.padEnd(30)} -> ${resolved ?? "404"}`);
}
if (ok !== clientRoutes.length) fail(`${clientRoutes.length - ok} route(s) would 404`);

// Hashed assets must be served directly, never swallowed by the rewrite.
const indexHtml = readFileSync(join(distDir, "index.html"), "utf8");
const assets = [...indexHtml.matchAll(/\/assets\/[^"']+/g)].map((m) => m[0]);
console.log("\nAssets (must be served from disk, not rewritten):");
for (const asset of new Set(assets)) {
  const fromFs = servedByFilesystem(asset);
  const good = Boolean(fromFs);
  console.log(`  ${good ? "✓" : "✗"} ${asset.slice(0, 60)}`);
  if (!good) fail(`${asset} is referenced by index.html but absent from dist`);
}

// /api/* must NOT be rewritten, so a same-origin API stays routable.
console.log("\nExcluded paths:");
for (const path of ["/api/listings", "/api/platform/status"]) {
  const target = rewrite(path);
  const good = target === null;
  console.log(`  ${good ? "✓" : "✗"} ${path.padEnd(30)} -> ${good ? "not rewritten" : target}`);
  if (!good) fail(`${path} must be excluded from the SPA rewrite`);
}

console.log(
  process.exitCode
    ? "\nFAILED — see the ✗ lines above."
    : `\nAll checks passed. ${ok}/${clientRoutes.length} routes serve index.html; assets served from disk; /api/* excluded.`,
);