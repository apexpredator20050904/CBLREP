/* eslint-disable react-refresh/only-export-components */
// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Shared UI primitives
// ─────────────────────────────────────────────────────────────
// Small Tailwind building blocks reused across admin pages: summary stat
// cards, status badges, empty states, and a generic data-table shell so
// every table (verification, moderation, users) looks consistent.
// ─────────────────────────────────────────────────────────────

export function StatCard({ icon, label, value, accent = false }) {
  return (
    <div
      className={`rounded-2xl border bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md ${
        accent ? "border-emerald-200" : "border-stone-200"
      }`}
    >
      <div className="text-2xl leading-none">{icon}</div>
      <p className="mt-3 text-[11px] font-bold uppercase tracking-wider text-stone-500">
        {label}
      </p>
      <p className="mt-1 text-3xl font-extrabold tabular-nums text-emerald-950">
        {value ?? 0}
      </p>
    </div>
  );
}

const BADGE_STYLES = {
  success: "bg-emerald-100 text-emerald-800",
  warn: "bg-amber-100 text-amber-800",
  danger: "bg-red-100 text-red-800",
  info: "bg-sky-100 text-sky-800",
  default: "bg-stone-100 text-stone-700",
};

export function StatusBadge({ tone = "default", children }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-bold ${
        BADGE_STYLES[tone] || BADGE_STYLES.default
      }`}
    >
      {children}
    </span>
  );
}

/** Map backend admin_status strings to badge tones. */
export function listingTone(status) {
  if (status === "Removed") return "danger";
  if (status === "Flagged") return "warn";
  if (status === "Hidden") return "info";
  return "success";
}

// ── Flexible compensation badges ─────────────────────────────────
// Distinct, unambiguous colours so a moderator can scan a table and tell a
// gift from a trade from a sale at a glance:
//   FREE SHARING → soft green, BARTER → warm amber, PAID → crisp blue.
const COMPENSATION_STYLES = {
  free: "bg-emerald-100 text-emerald-800 ring-emerald-200",
  barter: "bg-amber-100 text-amber-800 ring-amber-200",
  paid: "bg-sky-100 text-sky-800 ring-sky-200",
};

const COMPENSATION_FALLBACK = "bg-stone-100 text-stone-700 ring-stone-200";

/**
 * Render a listing's compensation type as a distinct badge.
 *
 * Accepts either the raw key (`free`/`barter`/`paid`) or the server's
 * pre-computed label. When `price` is supplied on a paid listing it is shown
 * as `PAID · ₱350`, mirroring the mobile app.
 */
export function CompensationBadge({ type, label, price, budget = false }) {
  const key = String(type || "").toLowerCase();
  const text =
    label ||
    { free: "FREE SHARING", barter: "BARTER", paid: "PAID" }[key] ||
    "BARTER";
  const showPrice =
    key === "paid" && price !== null && price !== undefined && price !== "";
  // On a NEED the figure is the poster's ceiling ("I can pay up to ₱300"),
  // not an asking price, so the badge must not read as one.
  const caption = budget && key === "paid" ? "BUDGET" : text;
  return (
    <span
      className={`inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-1 text-[10px] font-bold ring-1 ${
        COMPENSATION_STYLES[key] || COMPENSATION_FALLBACK
      }`}
    >
      {caption}
      {showPrice ? ` · ${budget ? "up to " : ""}₱${Number(price).toLocaleString()}` : ""}
    </span>
  );
}

/** Human label for a compensation key, used in filter dropdowns. */
export function compensationLabel(key) {
  return (
    { free: "FREE SHARING", barter: "BARTER", paid: "PAID" }[
      String(key || "").toLowerCase()
    ] || "BARTER"
  );
}

export function EmptyRow({ colSpan, children, icon = "📭" }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-12 text-center">
        <div className="mx-auto flex w-fit flex-col items-center gap-2 text-stone-500">
          <span className="text-3xl" aria-hidden>
            {icon}
          </span>
          <span className="text-sm">{children}</span>
        </div>
      </td>
    </tr>
  );
}

/** Friendly empty-state card with icon, title, message and optional action. */
export function EmptyState({ icon = "📭", title, message, action }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-stone-300 bg-stone-50 px-6 py-12 text-center">
      <div className="text-4xl" aria-hidden>
        {icon}
      </div>
      <h3 className="mt-3 text-sm font-extrabold text-emerald-950">{title}</h3>
      {message ? <p className="mt-1 max-w-sm text-xs text-stone-500">{message}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function PageHeader({ title, subtitle, actions }) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 className="text-2xl font-extrabold text-emerald-950">{title}</h1>
        {subtitle ? <p className="mt-1 text-sm text-stone-500">{subtitle}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export function FilterBar({ children, count }) {
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-xl border border-stone-200 bg-white p-3 shadow-sm">
      {children}
      {count ? <span className="ml-auto text-xs text-stone-500">{count}</span> : null}
    </div>
  );
}

export const selectClass =
  "rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm text-stone-700 focus:border-emerald-500 focus:outline-none";

export const dateInputClass =
  "rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm text-stone-700 focus:border-emerald-500 focus:outline-none";

export const btnPrimary =
  "rounded-lg bg-emerald-800 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-60";

export const btnGhost =
  "rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-emerald-950 hover:bg-emerald-50";

export const tableActionBtn =
  "rounded-md border border-stone-300 bg-white px-2.5 py-1 text-xs font-semibold text-emerald-950 hover:bg-emerald-50 disabled:opacity-50";

export const tableActionDanger =
  "rounded-md border border-red-200 bg-white px-2.5 py-1 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-50";

export const tableActionWarn =
  "rounded-md border border-amber-200 bg-white px-2.5 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-50 disabled:opacity-50";

export function TableCard({ title, children }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
      {title ? (
        <h2 className="border-b border-stone-100 px-5 py-3 text-sm font-bold text-emerald-950">
          {title}
        </h2>
      ) : null}
      <div className="overflow-x-auto">{children}</div>
    </div>
  );
}

export const tableClass = "min-w-full divide-y divide-stone-100 text-left text-sm";
export const theadClass = "bg-stone-50 text-xs uppercase tracking-wide text-stone-500";
export const thClass = "px-4 py-3 font-bold";
export const tdClass = "px-4 py-3 text-stone-700";
export const tdStrongClass = "px-4 py-3 font-semibold text-emerald-950";

/**
 * Member avatar: the uploaded photo when present, otherwise the member's
 * initials on a brand-green disc. The initials render underneath and the
 * photo overlays them, so a broken/expired URL degrades gracefully to the
 * initials (matching the mobile app) instead of a broken-image icon.
 *
 * Used in the verification queue and the users directory so a reviewer can
 * put a face to a submitted document.
 */
export function UserAvatar({ name, url, size = 36, className = "" }) {
  const initial = (name || "?").trim().charAt(0).toUpperCase() || "?";
  return (
    <span
      style={{ width: size, height: size }}
      className={`relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-emerald-800 text-xs font-bold text-white ${className}`}
      aria-hidden="true"
    >
      {initial}
      {url ? (
        <img
          src={url}
          alt={name || "Member"}
          className="absolute inset-0 h-full w-full object-cover"
          onError={(e) => {
            e.currentTarget.style.display = "none";
          }}
        />
      ) : null}
    </span>
  );
}
