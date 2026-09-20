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
  "Mabuhay",
  "Mahagbu",
  "Magsaysay",
  "San Isidro",
  "San Vicente",
  "Santo Niño",
  "Soom",
  "Tagum Norte",
  "Tagum Sur",
];

// Laravel backend is reached via the Vite dev-server proxy.
// The proxy forwards all /api/* requests to http://127.0.0.1:8000.
export const API_BASE_URL = "";

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
