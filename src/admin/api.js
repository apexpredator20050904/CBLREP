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
