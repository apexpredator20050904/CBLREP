export const getToken = () => localStorage.getItem("token");

export const apiFetch = async (path, options = {}) => {
  const res = await fetch(path, {
    ...options,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: `Bearer ${getToken()}`,
      ...(options.headers || {}),
    },
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message || `Request failed (${res.status})`);
  }
  return res.json();
};

// Deterministic barangay pin so every record is visible on the admin map.
const BARANGAY_COORDS = {
  "kinan-oan": [10.0824, 124.3231],
  bongbong: [10.0765, 124.3302],
  mahagbu: [10.0912, 124.3168],
  "san isidro": [10.0701, 124.3097],
  mabuhay: [10.0859, 124.3389],
  "tagum norte": [10.1015, 124.342],
  "la victoria": [10.0648, 124.3501],
};

export const pinForResource = (r) => {
  if (r.lat && r.lng) return [Number(r.lat), Number(r.lng)];
  const loc = String(r.location || "").toLowerCase();
  for (const key of Object.keys(BARANGAY_COORDS)) {
    if (loc.includes(key)) return BARANGAY_COORDS[key];
  }
  return null;
};

/**
 * Analytics export — opens the backend export endpoint in a new tab so the
 * browser handles the CSV/PDF download with the bearer token attached.
 * For CSV we can also trigger a programmatic download via the link href.
 */
export const exportAnalyticsUrl = (params = {}, fmt = "csv") => {
  const token = getToken();
  const q = new URLSearchParams();
  q.set("fmt", fmt);
  if (params.from) q.set("from", params.from);
  if (params.to) q.set("to", params.to);
  if (token) q.set("token", token);
  return `/api/admin/analytics/export?${q.toString()}`;
};

export const downloadCSV = (params = {}) => {
  // Opens in current window so the browser triggers the file download.
  window.location.href = exportAnalyticsUrl(params, "csv");
};

export const openPDF = (params = {}) => {
  // Opens the print-friendly HTML in a new tab for print-to-PDF.
  window.open(exportAnalyticsUrl(params, "pdf"), "_blank");
};
