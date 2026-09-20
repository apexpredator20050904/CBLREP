// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Axios API service layer (part 1: client + auth)
// ─────────────────────────────────────────────────────────────
// Single axios instance for the admin portal. Relative `/api/*` paths are
// forwarded by the Vite dev-server proxy to Laravel (127.0.0.1:8000).
// Auth model: Sanctum bearer tokens in localStorage (see AuthContext).
// ─────────────────────────────────────────────────────────────
import axios from "axios";

export const TOKEN_KEY = "token";
export const USER_KEY = "cblrep_user";

export const getToken = () => localStorage.getItem(TOKEN_KEY);

export const getStoredUser = () => {
  try {
    return JSON.parse(localStorage.getItem(USER_KEY) || "null");
  } catch {
    return null;
  }
};

export const clearStoredSession = () => {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem("cblrep_portal");
};

// Shared axios client — import this (not raw axios) in every module.
export const api = axios.create({
  baseURL: "/api",
  headers: { Accept: "application/json" },
  timeout: 20000,
});

// Attach the Sanctum bearer token to every request.
api.interceptors.request.use((config) => {
  const token = getToken();
  if (token) config.headers.Authorization = "Bearer " + token;
  return config;
});

// On 401 (expired/revoked token) wipe the session and bounce to login.
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err?.response?.status === 401 && window.location.pathname !== "/login") {
      clearStoredSession();
      window.location.assign("/login");
    }
    return Promise.reject(err);
  }
);

export const errMsg = (err, fallback) =>
  err?.response?.data?.message || fallback;

// ── Admin authentication ─────────────────────────────────────────

/**
 * POST /admin-login — verify admin credentials against Laravel.
 * Persists the Sanctum token + user profile for subsequent calls.
 */
export async function adminLogin({ email, password, adminCode }) {
  try {
    const { data } = await api.post("/admin-login", {
      email,
      password,
      adminCode: adminCode || undefined,
    });
    localStorage.setItem(TOKEN_KEY, data.access_token);
    localStorage.setItem(USER_KEY, JSON.stringify(data.user));
    localStorage.setItem("cblrep_portal", "admin");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Admin login failed."), { cause: err });
  }
}

/** POST /logout — revoke the current token, then wipe local session. */
export async function adminLogout() {
  try {
    await api.post("/logout");
  } catch {
    /* best-effort: still clear local state below */
  } finally {
    clearStoredSession();
  }
}

/** GET /user — current admin profile for the stored bearer token. */
export async function fetchCurrentAdmin() {
  try {
    const { data } = await api.get("/user");
    localStorage.setItem(USER_KEY, JSON.stringify(data));
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Session expired. Please sign in again."), { cause: err });
  }
}

/** GET /admin/dashboard — live totals for the overview stat cards. */
export async function fetchDashboardStats() {
  try {
    const { data } = await api.get("/admin/dashboard");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load dashboard statistics."), { cause: err });
  }
}

export async function fetchAdminSettings() {
  try {
    const { data } = await api.get("/admin/settings");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load system settings."), { cause: err });
  }
}

export async function saveAdminSettings(payload) {
  try {
    const { data } = await api.post("/admin/settings", payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to save system settings."), { cause: err });
  }
}

export async function clearAdminCache() {
  try {
    const { data } = await api.post("/admin/settings/cache/clear");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to clear application cache."), { cause: err });
  }
}

export async function downloadAdminBackup() {
  try {
    const response = await api.get("/admin/settings/backup", { responseType: "blob" });
    const disposition = response.headers["content-disposition"] || "";
    const filename = disposition.match(/filename="?([^"]+)"?/)?.[1] || "cblrep-trinidad-backup.sql";
    const url = URL.createObjectURL(response.data);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  } catch (err) {
    throw new Error(errMsg(err, "Failed to download database backup."), { cause: err });
  }
}

// ── Trinidad resident & barangay verification ────────────────────

/**
 * GET /admin/verification?barangay=… — pending registrations submitted from
 * the Flutter app, plus the decision history (audit trail).
 */
export async function fetchPendingVerifications(barangay = "") {
  try {
    const { data } = await api.get("/admin/verification", {
      params: barangay ? { barangay } : {},
    });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load verification queue."), { cause: err });
  }
}

/**
 * POST /admin/users/{id}/{action} — approve / reject / request-info /
 * suspend / reactivate a resident. `payload` carries e.g. { reason } or the
 * student capture { student_status, student_school } on verify.
 */
export async function decideVerification(id, action, payload = {}) {
  const allowed = ["verify", "reject", "request-info", "suspend", "reactivate"];
  if (!allowed.includes(action)) throw new Error(`Unsupported action: ${action}`);
  try {
    const { data } = await api.post(`/admin/users/${id}/${action}`, payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, `Verification ${action} failed.`), { cause: err });
  }
}

// ── Resource listing moderation (Offers / Needs) ─────────────────

/** GET /admin/resources?kind=all|offers|needs|flagged — listings to moderate. */
export async function fetchListings(kind = "all") {
  try {
    const { data } = await api.get("/admin/resources", { params: { kind } });
    return data.resources || [];
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load listings."), { cause: err });
  }
}

/**
 * POST /admin/resources/{id}/moderate — approve | flag | hide | remove |
 * restore a listing. Removals/hides require a reason (accountability).
 */
export async function moderateListing(id, action, reason = "") {
  try {
    const { data } = await api.post(`/admin/resources/${id}/moderate`, {
      action,
      reason,
    });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, `Listing ${action} failed.`), { cause: err });
  }
}

// ── Municipal analytics & report export ──────────────────────────

/** GET /admin/analytics?from=&to= — metrics for the summary cards. */
export async function fetchAnalytics({ from, to } = {}) {
  try {
    const { data } = await api.get("/admin/analytics", {
      params: { ...(from ? { from } : {}), ...(to ? { to } : {}) },
    });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load analytics."), { cause: err });
  }
}

/**
 * Export URL builder for GET /admin/analytics/export?fmt=csv|pdf.
 * The bearer token travels as `?token=` because plain <a>/window.open
 * downloads can't set Authorization headers.
 */
export function exportAnalyticsUrl({ from, to } = {}, fmt = "csv") {
  const q = new URLSearchParams({ fmt });
  if (from) q.set("from", from);
  if (to) q.set("to", to);
  const token = getToken();
  if (token) q.set("token", token);
  return `/api/admin/analytics/export?${q.toString()}`;
}

/** Trigger a CSV download of the analytics log. */
export function downloadAnalyticsCSV(params = {}) {
  window.location.href = exportAnalyticsUrl(params, "csv");
}

/** Open the print-friendly report in a new tab for print-to-PDF. */
export function openAnalyticsPDF(params = {}) {
  window.open(exportAnalyticsUrl(params, "pdf"), "_blank");
}

// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Content management API (part of adminApi service)
// Endpoints: GET/POST /admin/content, PATCH/DELETE /admin/content/{id}.
// ─────────────────────────────────────────────────────────────

/** GET /admin/content — summary { total, published, drafts } + rows. */
export async function fetchContentPages() {
  try {
    const { data } = await api.get("/admin/content");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load content pages."), { cause: err });
  }
}

/** POST /admin/content — create a draft or publish directly. */
export async function createContentPage(payload) {
  try {
    const { data } = await api.post("/admin/content", payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to save page."), { cause: err });
  }
}

/** PATCH /admin/content/{id} — edit title/slug/body or publish/unpublish. */
export async function updateContentPage(id, payload) {
  try {
    const { data } = await api.patch(`/admin/content/${id}`, payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to update page."), { cause: err });
  }
}

/** DELETE /admin/content/{id} — remove an outdated page. */
export async function deleteContentPage(id) {
  try {
    const { data } = await api.delete(`/admin/content/${id}`);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to delete page."), { cause: err });
  }
}

// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Notifications & announcements API
// Endpoints: GET/POST /admin/notifications,
//            POST /admin/notifications/{id}/send,
//            DELETE /admin/notifications/{id}.
// ─────────────────────────────────────────────────────────────

/** GET /admin/notifications — summary { total, sent, scheduled, drafts }. */
export async function fetchAnnouncements() {
  try {
    const { data } = await api.get("/admin/notifications");
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load announcements."), { cause: err });
  }
}

/** POST /admin/notifications — compose a draft / schedule / send-now. */
export async function createAnnouncement(payload) {
  try {
    const { data } = await api.post("/admin/notifications", payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to save announcement."), { cause: err });
  }
}

/** POST /admin/notifications/{id}/send — mark a draft/scheduled item sent. */
export async function sendAnnouncement(id) {
  try {
    const { data } = await api.post(`/admin/notifications/${id}/send`);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to broadcast announcement."), { cause: err });
  }
}

/** DELETE /admin/notifications/{id} — remove a draft/scheduled item. */
export async function deleteAnnouncement(id) {
  try {
    const { data } = await api.delete(`/admin/notifications/${id}`);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to delete announcement."), { cause: err });
  }
}

// Legacy pages under src/admin/ import { apiFetch, getToken,
// exportAnalyticsUrl, downloadCSV, openPDF } from "./api". Keep those names
// working by delegating to the axios client above.

/** Legacy fetch-style helper — delegates to the shared axios instance. */
export async function apiFetch(path, options = {}) {
  const url = path.replace(/^\/api/, "");
  try {
    const { data } = await api.request({
      url,
      method: options.method || "GET",
      data: options.body ? JSON.parse(options.body) : undefined,
      headers: options.headers,
    });
    return data;
  } catch (err) {
    const status = err?.response?.status || "network";
    throw new Error(errMsg(err, `Request failed (${status})`), { cause: err });
  }
}

/** Legacy CSV download alias. */
export const downloadCSV = (params = {}) => downloadAnalyticsCSV(params);

/** Legacy PDF alias. */
export const openPDF = (params = {}) => openAnalyticsPDF(params);
