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

export function EmptyRow({ colSpan, children }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-10 text-center text-sm text-stone-500">
        {children}
      </td>
    </tr>
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
