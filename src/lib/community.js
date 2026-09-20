// src/lib/community.js
// Backwards-compatibility shim — the canonical helpers live in
// src/config/community.js. Kept so any stale `lib/community` import
// keeps resolving after the Express -> Laravel migration.
export * from "../config/community";
