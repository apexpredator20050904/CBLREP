// ─────────────────────────────────────────────────────────────
// CBLRE Admin · Live listings map (/admin/map)
// OpenStreetMap tiles via react-leaflet; markers for every active
// offer / need with a rich popup (photo + details). Polls the
// backend so newly posted listings appear live.
// ─────────────────────────────────────────────────────────────
import { useCallback, useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker, Popup, Circle, useMap, useMapEvents } from "react-leaflet";
import L from "leaflet";
import AdminLayout from "../components/AdminLayout";
import { CompensationBadge } from "../components/ui";
import { useAutoRefresh } from "../hooks/useAutoRefresh";
import { api } from "../services/adminApi";

const TRINIDAD_CENTER = [10.0797, 124.3431];

const pin = (color) =>
  L.divIcon({
    className: "",
    html: `<span style="display:block;width:16px;height:16px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);background:${color};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)"></span>`,
    iconSize: [18, 18],
    iconAnchor: [9, 18],
    popupAnchor: [0, -16],
  });

const offerPin = pin("#e58824");
const needPin = pin("#1b3b22");

function UserLocation({ onFix }) {
  const map = useMap();
  useMapEvents({});
  useEffect(() => {
    if (!("geolocation" in navigator)) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const here = [pos.coords.latitude, pos.coords.longitude];
        onFix?.(here);
        map.flyTo(here, Math.max(map.getZoom(), 14), { duration: 1.2 });
      },
      () => {},
      { enableHighAccuracy: true, timeout: 8000 }
    );
  }, [map, onFix]);
  return null;
}

export default function MapPage() {
  const [rows, setRows] = useState([]);
  const [userPos, setUserPos] = useState(null);
  const [filter, setFilter] = useState("all");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    try {
      const { data } = await api.get("/admin/map", { params: { filter: filter === "all" ? "all" : filter } });
      setRows(data.resources || []);
      setError("");
    } catch (e) {
      setError(e?.response?.data?.message || "Failed to load map data.");
    }
  }, [filter]);

  // Initial load, then a hardened 15s live poll (also refreshes on tab focus).
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);
  useAutoRefresh(load, 15000);

  const visible = rows.filter((r) => r.lat != null && r.lng != null);

  return (
    <AdminLayout title="Live Listings Map" toast={error}>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        {["all", "offers", "needs"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`rounded-full border px-3 py-1 text-xs font-semibold capitalize transition ${
              filter === f ? "border-emerald-800 bg-emerald-900 text-white" : "border-stone-300 bg-white text-stone-700"
            }`}
          >
            {f}
          </button>
        ))}
        <span className="ml-auto text-xs text-stone-500 dark:text-stone-400">{visible.length} pins · live</span>
      </div>

      <div className="overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm" style={{ height: "70vh" }}>
        <MapContainer center={TRINIDAD_CENTER} zoom={13} style={{ height: "100%", width: "100%" }}>
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <UserLocation onFix={setUserPos} />
          {userPos && (
            <Circle center={userPos} radius={60} pathOptions={{ color: "#2563eb", fillOpacity: 0.15 }} />
          )}
          {visible.map((r) => (
            <Marker
              key={r.id}
              position={[Number(r.lat), Number(r.lng)]}
              icon={r.type?.toLowerCase() === "need" || r.type?.toLowerCase() === "request" ? needPin : offerPin}
            >
              <Popup>
                <div className="w-56">
                  {r.image_url && (
                    <img src={r.image_url} alt={r.title} className="mb-2 h-28 w-full rounded-md object-cover" />
                  )}
                  <p className="text-sm font-bold">{r.title}</p>
                  <div className="my-1">
                    <CompensationBadge
                      type={r.compensation_type}
                      label={r.compensation_label}
                      price={r.price}
                    />
                  </div>
                  <p className="text-xs text-stone-500">
                    {r.type} · {r.category}
                  </p>
                  <p className="text-xs text-stone-500">
                    {[r.barangay, r.purok_sitio].filter(Boolean).join(" · ") || r.location || "Trinidad, Bohol"}
                  </p>
                  <p className="mt-1 text-xs text-stone-600">Owner: {r.owner}</p>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>
    </AdminLayout>
  );
}
