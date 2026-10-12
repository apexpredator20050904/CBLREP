export const COMMUNITY = {
  municipality: "Trinidad",
  province: "Bohol",
  country: "Philippines",
  label: "Trinidad, Bohol, Philippines",
  shortLabel: "Trinidad, Bohol",
  center: [10.0797, 124.3431],
  defaultZoom: 14,
};

export const TRINIDAD_BARANGAYS = [
  "Banlasan",
  "Bongbong",
  "Catoogan",
  "Guinobatan",
  "Hinlayagan Ilaud",
  "Hinlayagan Ilaya",
  "Kauswagan",
  "Kinan-oan",
  "La Union",
  "La Victoria",
  "Mabuhay Cabigohan",
  "Mahagbu",
  "Manuel M. Roxas",
  "Poblacion",
  "San Isidro",
  "San Vicente",
  "Santo Tomas",
  "Soom",
  "Tagum Norte",
  "Tagum Sur",
];

// Origin of the Laravel backend (no trailing slash, no `/api` suffix).
//
// Empty by default: the app issues relative `/api/*` requests that the Vite
// dev-server forwards to the backend named by VITE_API_TARGET (see
// vite.config.js). Staying same-origin means no CORS preflight is required
// while developing — including when a phone loads the app from the dev server
// over the LAN at http://<PC-IP>:5173.
//
// Set VITE_API_BASE_URL in frontend/.env (e.g. http://192.168.1.74:8000) to
// call the Laravel API directly instead. Required for a production build
// served from a static host such as Vercel; Laravel CORS must allow that
// origin (backend/config/cors.php). The value is inlined at build time, so
// setting it on Vercel requires a new deployment to take effect.
export const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || "").replace(/\/+$/, "");

// In a production build an unset base URL means every request goes to the
// Vercel origin and the admin console silently 404s. Surface it once at boot
// instead of leaving the operator to debug an empty table.
if (import.meta.env.PROD && !API_BASE_URL) {
  console.warn(
    "[CBLREP] VITE_API_BASE_URL is not set — API requests will use same-origin /api/*. " +
      "Set it in the Vercel project environment variables to the Laravel API origin.",
  );
}

export const isAdminUser = (user) => {
  if (!user) return false;
  if (user.is_admin === true) return true;
  const role = String(user.role || "").toLowerCase();
  return role.includes("admin") || role.includes("system administrator");
};

export const persistSession = (user, token, portal) => {
  localStorage.setItem("token", token);
  localStorage.setItem("cblrep_user", JSON.stringify(user));
  localStorage.setItem("cblrep_portal", portal);
};

export const clearSession = () => {
  localStorage.removeItem("token");
  localStorage.removeItem("cblrep_user");
  localStorage.removeItem("cblrep_portal");
};

export const readSession = () => {
  try {
    const token = localStorage.getItem("token");
    const portal = localStorage.getItem("cblrep_portal");
    const user = JSON.parse(localStorage.getItem("cblrep_user") || "null");
    if (!token || !user || !portal) return null;
    return { token, user, portal };
  } catch {
    return null;
  }
};

export const communityLocation = (barangay) => {
  if (!barangay) return COMMUNITY.label;
  if (String(barangay).includes("Trinidad")) return barangay;
  return `${barangay}, ${COMMUNITY.shortLabel}`;
};
