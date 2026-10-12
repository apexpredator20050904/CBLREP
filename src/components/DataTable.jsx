// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Reusable advanced data table (Tailwind)
// ─────────────────────────────────────────────────────────────
// One table component for every management module (users, accounts,
// exchanges, listings, approvals). Features:
//   • per-column filter row (text or select inputs)
//   • global search box
//   • sortable column headers (asc → desc → off)
//   • client-side OR server-side filtering/sorting/pagination
//   • loading, empty and error states
//
// Column config:
//   {
//     key:      "name",                  // row field (or getValue)
//     label:    "Name",
//     sortable: true,                    // header click sorts
//     filter:   { type: "text" }         // or { type: "select", options: [...] }
//     getValue: (row) => string,         // custom accessor (defaults row[key])
//     render:   (row) => JSX,            // custom cell (defaults the value)
//   }
//
// Server mode: pass serverMode + page/totalCount/onQueryChange — the
// component stops filtering internally and emits
// { q, filters, sort_by, sort_dir, page, per_page } on every change.
// ─────────────────────────────────────────────────────────────
import { useEffect, useMemo, useState } from "react";
import { EmptyRow, tableClass, tdClass, thClass, theadClass } from "./ui";

const inputClass =
  "w-full rounded-md border border-stone-300 bg-white px-2 py-1.5 text-xs text-stone-700 placeholder:text-stone-400 focus:border-emerald-500 focus:outline-none";

export default function DataTable({
  columns,
  rows = [],
  loading = false,
  emptyMessage = "No records found.",
  initialSort = null, // { key, dir }
  pageSize: initialPageSize = 10,
  globalSearch = true,
  serverMode = false,
  page = 1,
  totalCount = null,
  onQueryChange = null,
  toolbar = null,
  rowKey = (row) => row.id,
}) {
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState({});
  const [sort, setSort] = useState(initialSort); // { key, dir: "asc"|"desc" }
  const [pageSize, setPageSize] = useState(initialPageSize);
  const [clientPage, setClientPage] = useState(1);

  const accessor = (column, row) =>
    column.getValue ? String(column.getValue(row) ?? "") : String(row[column.key] ?? "");

  // Notify the parent in server mode.
  useEffect(() => {
    if (serverMode && onQueryChange) {
      onQueryChange({ q: query, filters, sort_by: sort?.key, sort_dir: sort?.dir, page, per_page: pageSize });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [serverMode, query, filters, sort, page, pageSize]);

  // ── Client-side pipeline (skipped in server mode) ────────────────
  const processed = useMemo(() => {
    if (serverMode) return rows;
    let out = [...rows];

    if (query.trim()) {
      const q = query.trim().toLowerCase();
      out = out.filter((row) =>
        columns.some((c) => accessor(c, row).toLowerCase().includes(q)),
      );
    }
    for (const [key, value] of Object.entries(filters)) {
      if (!value) continue;
      const column = columns.find((c) => c.key === key);
      if (!column) continue;
      const v = String(value).toLowerCase();
      out = out.filter((row) => {
        const cell = accessor(column, row).toLowerCase();
        return column.filter?.type === "select" ? cell === v : cell.includes(v);
      });
    }
    if (sort?.key) {
      const column = columns.find((c) => c.key === sort.key);
      if (column) {
        out.sort((a, b) => {
          const av = accessor(column, a);
          const bv = accessor(column, b);
          const an = parseFloat(av);
          const bn = parseFloat(bv);
          const cmp =
            !Number.isNaN(an) && !Number.isNaN(bn) && av !== "" && bv !== ""
              ? an - bn
              : av.localeCompare(bv);
          return sort.dir === "asc" ? cmp : -cmp;
        });
      }
    }
    return out;
  }, [serverMode, rows, query, filters, sort, columns]);

  const effectiveTotal = serverMode ? (totalCount ?? rows.length) : processed.length;
  const effectivePage = serverMode ? page : clientPage;
  const lastPage = Math.max(1, Math.ceil(effectiveTotal / pageSize));
  const safePage = Math.min(effectivePage, lastPage);

  const pageRows = useMemo(() => {
    if (serverMode) return rows;
    const start = (safePage - 1) * pageSize;
    return processed.slice(start, start + pageSize);
  }, [serverMode, rows, processed, safePage, pageSize]);

  // Reset to page 1 whenever the dataset shrinks past the cursor.
  useEffect(() => {
    if (!serverMode && (safePage - 1) * pageSize >= processed.length && safePage > 1) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setClientPage(1);
    }
  }, [processed.length, safePage, pageSize, serverMode]);

  const toggleSort = (key) => {
    setSort((prev) =>
      prev?.key !== key ? { key, dir: "asc" } : prev.dir === "asc" ? { key, dir: "desc" } : null,
    );
    setClientPage(1);
  };

  const setFilter = (key, value) => {
    setFilters((prev) => ({ ...prev, [key]: value }));
    setClientPage(1);
  };

  return (
    <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
      {(globalSearch || toolbar) && (
        <div className="flex flex-wrap items-center gap-2 border-b border-stone-100 px-4 py-3">
          {toolbar}
          {globalSearch && (
            <input
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                setClientPage(1);
              }}
              placeholder="Search all columns…"
              className="ml-auto w-56 rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none"
            />
          )}
        </div>
      )}

      <div className="overflow-x-auto">
        <table className={tableClass}>
          <thead className={theadClass}>
            <tr>
              {columns.map((c) => (
                <th key={c.key} className={thClass}>
                  {c.sortable ? (
                    <button
                      type="button"
                      onClick={() => toggleSort(c.key)}
                      className="inline-flex items-center gap-1 hover:text-emerald-800"
                    >
                      {c.label}
                      <span className="text-[10px]">
                        {sort?.key === c.key ? (sort.dir === "asc" ? "▲" : "▼") : "↕"}
                      </span>
                    </button>
                  ) : (
                    c.label
                  )}
                </th>
              ))}
            </tr>
            {/* Per-column filter row */}
            <tr>
              {columns.map((c) => (
                <th key={c.key} className="px-4 pb-2">
                  {c.filter?.type === "select" ? (
                    <select
                      value={filters[c.key] || ""}
                      onChange={(e) => setFilter(c.key, e.target.value)}
                      className={inputClass}
                    >
                      <option value="">All</option>
                      {(c.filter.options || []).map((o) => (
                        <option key={o.value ?? o} value={o.value ?? o}>
                          {o.label ?? o}
                        </option>
                      ))}
                    </select>
                  ) : c.filter?.type === "text" ? (
                    <input
                      value={filters[c.key] || ""}
                      onChange={(e) => setFilter(c.key, e.target.value)}
                      placeholder={`Filter ${c.label.toLowerCase()}…`}
                      className={inputClass}
                    />
                  ) : null}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {loading ? (
              <tr>
                <td colSpan={columns.length} className="px-4 py-10 text-center text-sm text-stone-500">
                  Loading…
                </td>
              </tr>
            ) : pageRows.length === 0 ? (
              <EmptyRow colSpan={columns.length}>{emptyMessage}</EmptyRow>
            ) : (
              pageRows.map((row) => (
                <tr key={rowKey(row)} className="hover:bg-stone-50">
                  {columns.map((c) => (
                    <td key={c.key} className={c.strong ? "px-4 py-3 font-semibold text-emerald-950" : tdClass}>
                      {c.render ? c.render(row) : accessor(c, row) || "—"}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination footer */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-stone-100 px-4 py-3 text-xs text-stone-500">
        <span>
          {effectiveTotal === 0
            ? "0 results"
            : `Showing ${(safePage - 1) * pageSize + 1}–${Math.min(safePage * pageSize, effectiveTotal)} of ${effectiveTotal}`}
        </span>
        <div className="flex items-center gap-2">
          <select
            value={pageSize}
            onChange={(e) => {
              setPageSize(Number(e.target.value));
              setClientPage(1);
            }}
            className="rounded-md border border-stone-300 bg-white px-2 py-1"
          >
            {[5, 10, 25, 50].map((n) => (
              <option key={n} value={n}>{n} / page</option>
            ))}
          </select>
          <button
            type="button"
            disabled={safePage <= 1}
            onClick={() => {
              if (serverMode) onQueryChange?.({ page: safePage - 1, per_page: pageSize });
              else setClientPage(safePage - 1);
            }}
            className="rounded-md border border-stone-300 px-2.5 py-1 font-semibold hover:bg-stone-50 disabled:opacity-40"
          >
            ‹ Prev
          </button>
          <span className="tabular-nums">Page {safePage} / {lastPage}</span>
          <button
            type="button"
            disabled={safePage >= lastPage}
            onClick={() => {
              if (serverMode) onQueryChange?.({ page: safePage + 1, per_page: pageSize });
              else setClientPage(safePage + 1);
            }}
            className="rounded-md border border-stone-300 px-2.5 py-1 font-semibold hover:bg-stone-50 disabled:opacity-40"
          >
            Next ›
          </button>
        </div>
      </div>
    </div>
  );
}
