// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Axios API service layer (part 1: client + auth)
// ─────────────────────────────────────────────────────────────
// Single axios instance for the admin portal.
//
// When VITE_API_BASE_URL is unset (the default), relative `/api/*` paths are
// forwarded by the Vite dev-server proxy to the Laravel backend (see
// vite.config.js). When it is set to the LAN origin (e.g.
// http://192.168.0.231:8000), requests go straight to Laravel and CORS applies.
// Auth model: Sanctum bearer tokens in localStorage (see AuthContext).
// ─────────────────────────────────────────────────────────────
import axios from "axios";
import { API_BASE_URL } from "../config/community.js";

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
  baseURL: API_BASE_URL ? `${API_BASE_URL}/api` : "/api",
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
//
// The 2FA stage-2 endpoints are excluded. They answer 401 to a *wrong OTP*,
// which is an ordinary part of the sign-in flow — redirecting there would
// discard the challenge token the modal is holding and trap the operator
// back on the credentials form. `authRequired` marks calls that genuinely
// require an established session.
// Endpoints reachable *before* a session exists: stage 1 of the two-factor
// flow and the login-time enrolment calls (authenticated by an enrol token
// in the body, not a bearer header). The Settings enrolment calls DO carry a
// bearer header and stay subject to the redirect — a 401 there means a
// genuinely dead session.
const AUTH_EXEMPT = ["/admin-login", "/admin/2fa/verify", "/admin/2fa/enrol"];

api.interceptors.response.use(
  (res) => res,
  (err) => {
    const url = err?.config?.url || "";
    const isStage2 = AUTH_EXEMPT.some((p) => url.includes(p));

    if (err?.response?.status === 401 && !isStage2 && window.location.pathname !== "/login") {
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
 * Persist an authenticated admin session. Shared by stage 1 (no 2FA) and
 * stage 2 (code redeemed) so both paths write an identical session shape.
 */
function persistSession(data) {
  localStorage.setItem(TOKEN_KEY, data.access_token);
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  localStorage.setItem("cblrep_portal", "admin");
  return data;
}

/**
 * POST /admin-login — verify admin credentials against Laravel.
 *
 * Returns a prompt payload — never a session, so no token is stored here:
 *
 *   - enrolled account   → `{ requires_2fa: true, challenge_token }`
 *   - unenrolled account → `{ requires_enrolment: true, enrol_token,
 *     qr_code, secret, issuer }` — the login-time QR step
 *
 * The session is minted only by verifyAdminTwoFactor() (code entry),
 * confirmLoginEnrolment() (QR confirmed) or skipLoginEnrolment() (declined).
 * Callers must branch on the flags; treating a prompt payload as a session
 * would leave `data.access_token` undefined and every later request
 * unauthenticated.
 */
export async function adminLogin({ email, password }) {
  try {
    const { data } = await api.post("/admin-login", {
      email,
      password,
    });

    if (data.requires_2fa || data.requires_enrolment) return data; // prompt only
    return persistSession(data);
  } catch (err) {
    throw new Error(errMsg(err, "Admin login failed."), { cause: err });
  }
}

/**
 * POST /admin/2fa/verify — redeem the authenticator code and receive the
 * session. This is the only call that mints the Sanctum token for a 2FA
 * account.
 *
 * `code` accepts a 6-digit TOTP value or a recovery code (A1B2-C3D4); the
 * server routes between them. It deliberately does NOT catch and rewrap 401:
 * the response interceptor treats a 401 here as an ordinary "wrong code"
 * rather than a dead session, so the error must reach the caller intact.
 */
export async function verifyAdminTwoFactor({ challengeToken, code }) {
  const { data } = await api.post("/admin/2fa/verify", {
    challenge_token: challengeToken,
    code,
  });
  return persistSession(data);
}

// ── Login-time enrolment (no session exists yet) ────────────────────
// Both calls authenticate with the enrol_token from stage 1, not a bearer
// header, and both answer 422/429 (never 401) on failure, so the response
// interceptor treats a bad scan as an ordinary form error.

/**
 * POST /admin/2fa/enrol/confirm — redeem the first code scanned from the
 * login QR. Succeeds only while the enrol_token is live; the response
 * carries the one-time recovery codes on top of the session.
 */
export async function confirmLoginEnrolment({ enrolToken, code }) {
  const { data } = await api.post("/admin/2fa/enrol/confirm", {
    enrol_token: enrolToken,
    code,
  });
  return persistSession(data);
}

/**
 * POST /admin/2fa/enrol/skip — decline enrolment for now and sign in with a
 * password-only session. Destroys the pending QR server-side, so the code
 * on screen can never be confirmed afterwards.
 */
export async function skipLoginEnrolment({ enrolToken }) {
  const { data } = await api.post("/admin/2fa/enrol/skip", {
    enrol_token: enrolToken,
  });
  return persistSession(data);
}

// ── Enrolment (signed-in admins, from the Settings screen) ─────────
// Authenticated calls: a failure here means a broken session, so the shared
// interceptor's redirect-to-login is the correct response.

// POST /admin/2fa/setup — mint a secret and render the QR code. Nothing is
// persisted yet; the secret waits in cache until confirm() proves it was
// actually scanned.
export async function beginTwoFactorSetup() {
  const { data } = await api.post("/admin/2fa/setup");
  return data; // { secret, qr_code, provisioning_uri, issuer, expires_in }
}

// POST /admin/2fa/setup/confirm — switch the factor on. Returns the
// plaintext recovery codes, which are shown exactly once and never stored.
//
// The response also carries a rotated session token. Confirming the factor
// revokes the token the admin enrolled with, because the server refuses
// non-2FA tokens from that moment on. Persisting here is what stops the
// next request going out with a token that no longer exists.
export async function confirmTwoFactorSetup(code) {
  const { data } = await api.post("/admin/2fa/setup/confirm", { code });
  return persistSession(data); // adds access_token / user on top of the payload
}

// POST /admin/2fa/disable — turn the factor off. Requires the account
// password AND a live code, so a hijacked session alone cannot strip it.
export async function disableTwoFactor({ password, code }) {
  const { data } = await api.post("/admin/2fa/disable", { password, code });
  return data;
}

// POST /admin/2fa/recovery-codes — issue a fresh set, invalidating the old.
export async function regenerateRecoveryCodes({ password, code }) {
  const { data } = await api.post("/admin/2fa/recovery-codes", { password, code });
  return data; // { message, recovery_codes }
}

// GET /admin/2fa/status — is the factor on, and how many codes are left?
export async function fetchTwoFactorStatus() {
  const { data } = await api.get("/admin/2fa/status");
  return data; // { enabled, confirmed_at, recovery_codes_remaining }
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

/**
 * GET /admin/verification/{id}/document — fetch the member's submitted proof
 * of residency as an authenticated blob and open it in a new tab.
 *
 * Proof documents are private, so the endpoint is bearer-token guarded and a
 * plain <a href> cannot be used (the token lives in localStorage, not a
 * cookie). The object URL is revoked shortly after the tab has the data.
 */
export async function openVerificationDocument(id) {
  try {
    const { data } = await api.get(`/admin/verification/${id}/document`, {
      responseType: "blob",
      timeout: 30000,
    });
    const url = URL.createObjectURL(data);
    window.open(url, "_blank", "noopener,noreferrer");
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    return true;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to open verification document."), { cause: err });
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

// ── Direct inquiries (listing-scoped messaging oversight) ────────
// Members negotiate free/barter/paid exchanges in the Flutter app; the
// console can read every inquiry and post an official reply.

/** GET /admin/inquiries?q=&listing_id= — listing-scoped conversations. */
export async function fetchInquiries({ q = "", listingId = "" } = {}) {
  try {
    const { data } = await api.get("/admin/inquiries", {
      params: {
        ...(q ? { q } : {}),
        ...(listingId ? { listing_id: listingId } : {}),
      },
    });
    return data.inquiries || [];
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load inquiries."), { cause: err });
  }
}

/** GET /admin/inquiries/{id} — full thread for one inquiry. */
export async function fetchInquiry(id) {
  try {
    const { data } = await api.get(`/admin/inquiries/${id}`);
    return data; // { inquiry, messages }
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load the inquiry."), { cause: err });
  }
}

/** POST /admin/inquiries/{id}/reply — post an official admin reply. */
export async function replyToInquiry(id, body) {
  try {
    const { data } = await api.post(`/admin/inquiries/${id}/reply`, { body });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to send the reply."), { cause: err });
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
 * Pull a binary export as a Blob.
 *
 * Axios is used (rather than a plain <a href> or window.open) so the Sanctum
 * bearer token stays in the Authorization header. The previous implementation
 * passed it as `?token=`, which leaked the credential into browser history,
 * server access logs and any Referer header.
 */
async function fetchExportBlob(path, params, fallback) {
  try {
    const { data, headers } = await api.get(path, {
      params: {
        ...(params?.from ? { from: params.from } : {}),
        ...(params?.to ? { to: params.to } : {}),
      },
      // Without this, axios hands back a string and the binary gets mangled.
      responseType: "blob",
    });

    return { blob: data, filename: filenameFromHeaders(headers) };
  } catch (err) {
    // A failed export is still a Blob, so the JSON error body has to be read
    // out of it manually before the user sees a generic network message.
    throw new Error(await readBlobError(err, fallback), { cause: err });
  }
}

/**
 * Pull the server-generated filename out of Content-Disposition.
 * Falls back to a sensible default when the header is absent.
 */
function filenameFromHeaders(headers = {}) {
  const disposition = headers["content-disposition"] || "";
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition);
  return match ? decodeURIComponent(match[1].trim()) : null;
}

/** Unwrap a JSON error body that arrived as a Blob. */
async function readBlobError(err, fallback) {
  const body = err?.response?.data;
  if (body instanceof Blob) {
    try {
      const text = await body.text();
      return JSON.parse(text)?.message || fallback;
    } catch {
      return fallback;
    }
  }
  return body?.message || fallback;
}

/**
 * Hand a Blob to the browser as a file download.
 *
 * The temporary <a> is removed from the DOM in a finally block — leaving it
 * attached leaks the anchor for the page's lifetime. The object URL is revoked
 * on a short timer rather than immediately, because Safari can cancel an
 * in-flight download if the URL is released in the same tick as the click.
 */
function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");

  try {
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
  } finally {
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
}

/** Export the analytics report as CSV. Resolves to the saved filename. */
export async function exportAnalyticsCSV(params = {}) {
  const { blob, filename } = await fetchExportBlob(
    "/admin/analytics/export/csv",
    params,
    "CSV export failed. Please try again."
  );

  const name = filename || `cblrep-trinidad-analytics-${Date.now()}.csv`;
  saveBlob(blob, name);
  return name;
}

/** Export the analytics report as a real PDF. Resolves to the saved filename. */
export async function exportAnalyticsPDF(params = {}) {
  const { blob, filename } = await fetchExportBlob(
    "/admin/analytics/export/pdf",
    params,
    "PDF export failed. Please try again."
  );

  const name = filename || `cblrep-trinidad-analytics-report-${Date.now()}.pdf`;
  saveBlob(blob, name);
  return name;
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

// ── User & role management (AdminAccountsPage) ───────────────────
// Endpoints: GET/POST /admin/accounts, PATCH /admin/accounts/{id},
//            PATCH /admin/accounts/{id}/role, DELETE /admin/accounts/{id}.

/** GET /admin/accounts — server-side filtered/sorted/paginated account list. */
export async function fetchAccounts({
  q = "",
  filters = {},
  sort_by,
  sort_dir,
  page = 1,
  per_page = 10,
} = {}) {
  try {
    const params = { page, per_page };
    if (q) params.q = q;
    if (sort_by) params.sort_by = sort_by;
    if (sort_dir) params.sort_dir = sort_dir;
    for (const [key, value] of Object.entries(filters)) {
      if (value) params[`filter_${key}`] = value;
    }
    const { data } = await api.get("/admin/accounts", { params });
    return {
      rows: data.data || data.users || [],
      meta: data.meta || { total: data.total ?? (data.data || []).length },
    };
  } catch (err) {
    throw new Error(errMsg(err, "Failed to load accounts."), { cause: err });
  }
}

/** POST /admin/accounts — create a user/admin account (hashed server-side). */
export async function createAccount(payload) {
  try {
    const { data } = await api.post("/admin/accounts", payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to create account."), { cause: err });
  }
}

/** PATCH /admin/accounts/{id} — edit profile / reset password / suspend. */
export async function updateAccount(id, payload) {
  try {
    const { data } = await api.patch(`/admin/accounts/${id}`, payload);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to update account."), { cause: err });
  }
}

/** PATCH /admin/accounts/{id}/role — Super Admin only (server-enforced). */
export async function updateAccountRole(id, role) {
  try {
    const { data } = await api.patch(`/admin/accounts/${id}/role`, { role });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to change role."), { cause: err });
  }
}

/** DELETE /admin/accounts/{id} — Super Admin only (server-enforced). */
export async function deleteAccount(id) {
  try {
    const { data } = await api.delete(`/admin/accounts/${id}`);
    return data;
  } catch (err) {
    throw new Error(errMsg(err, "Failed to delete account."), { cause: err });
  }
}

// ── Secure approval workflows ─────────────────────────────────────

/**
 * POST /admin/exchanges/{id}/approve — approve | decline | cancel an
 * exchange with audit logging + member notifications (server-side).
 *
 * Dual-confirmation: admins CANNOT complete a trade — completion happens
 * only when both members confirm via POST /api/exchanges/{id}/
 * confirm-completion on the mobile app. The console renders the
 * dual-confirmation progress read-only instead.
 */
export async function approveExchange(id, status, reason = "") {
  try {
    const { data } = await api.post(`/admin/exchanges/${id}/approve`, {
      status,
      reason: reason || undefined,
    });
    return data;
  } catch (err) {
    throw new Error(errMsg(err, `Exchange ${status} failed.`), { cause: err });
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
export const downloadCSV = (params = {}) => exportAnalyticsCSV(params);

/** Legacy PDF alias. */
export const openPDF = (params = {}) => exportAnalyticsPDF(params);
