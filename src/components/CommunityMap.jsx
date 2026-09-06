import { useEffect, useMemo } from "react";
import { MapContainer, TileLayer, Marker, Popup, Circle, useMap } from "react-leaflet";
import L from "leaflet";
import markerIcon2x from "leaflet/dist/images/marker-icon-2x.png";
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";
import { COMMUNITY } from "../config/community";

delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
});

const liveIcon = L.divIcon({
  className: "live-marker-wrap",
  html: '<span class="live-marker-pulse"></span><span class="live-marker-dot"></span>',
  iconSize: [22, 22],
  iconAnchor: [11, 11],
});

const memberIcon = L.divIcon({
  className: "live-marker-wrap",
  html: '<span class="member-marker-dot"></span>',
  iconSize: [14, 14],
  iconAnchor: [7, 7],
});

function FollowLive({ position, enabled }) {
  const map = useMap();
  useEffect(() => {
    if (enabled && position) {
      map.flyTo(position, Math.max(map.getZoom(), 15), { duration: 0.7 });
    }
  }, [enabled, map, position]);
  return null;
}

export default function CommunityMap({
  resources = [],
  radiusMeters = 2000,
  userPosition = null,
  members = [],
  followLive = true,
}) {
  const fallback = COMMUNITY.center;
  const center = userPosition || fallback;

  const otherMembers = useMemo(
    () =>
      (members || []).filter(
        (m) => m.lat && m.lng && (m.id !== "self"),
      ),
    [members],
  );

  return (
    <div className="map-canvas">
      <MapContainer
        center={fallback}
        zoom={COMMUNITY.defaultZoom}
        scrollWheelZoom
        className="map-leaflet"
      >
        <TileLayer
          attribution='&copy; OpenStreetMap contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FollowLive position={center} enabled={followLive} />
        <Circle
          center={center}
          radius={radiusMeters}
          pathOptions={{
            color: "#1b382b",
            fillColor: "#2d6a4f",
            fillOpacity: 0.12,
            weight: 2,
          }}
        />
        <Marker position={fallback}>
          <Popup>
            <strong>{COMMUNITY.label}</strong>
            <br />
            Community center
          </Popup>
        </Marker>
        {userPosition ? (
          <Marker position={userPosition} icon={liveIcon}>
            <Popup>
              You are here
              <br />
              Live GPS · Trinidad monitoring radius
            </Popup>
          </Marker>
        ) : null}
        {otherMembers.map((member) => (
          <Marker
            key={member.id}
            position={[member.lat, member.lng]}
            icon={memberIcon}
          >
            <Popup>
              {member.name || "Neighbor"}
              <br />
              Live in {COMMUNITY.shortLabel}
            </Popup>
          </Marker>
        ))}
        {resources.map((resource) =>
          resource.lat && resource.lng ? (
            <Marker key={resource.id} position={[resource.lat, resource.lng]}>
              <Popup>
                <strong>{resource.title}</strong>
                <br />
                {resource.category} · {resource.exchange_type}
              </Popup>
            </Marker>
          ) : null,
        )}
      </MapContainer>
    </div>
  );
}
