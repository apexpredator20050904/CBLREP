import 'dart:math' show pi, sin, cos, sqrt, asin, pow;

const trinidadBarangays = <String>[
  'Poblacion',
  'Banlasan',
  'Bongbong',
  'Catoogan',
  'Guinobatan',
  'Hinlayagan Ilaud',
  'Hinlayagan Ilaya',
  'Kauswagan',
  'Kinan-oan',
  'La Union',
  'La Victoria',
  'Mabuhay Cabigohan',
  'Mahagbu',
  'Manuel M. Roxas',
  'San Isidro',
  'San Vicente',
  'Santo Tomas',
  'Soom',
  'Tagum Norte',
  'Tagum Sur',
];

const communityName = 'Trinidad, Bohol';

/// Municipal centre of Trinidad, Bohol used to anchor the community map.
const trinidadCenter = (lat: 10.0797, lng: 124.3431);

/// Approximate anchor coordinates for each barangay, distributed around the
/// municipal centre. They let the community map place real, deterministic
/// markers and run proximity filtering until the backend stores exact GPS
/// points per listing (listings inherit their barangay's anchor).
const barangayCoordinates = <String, (double, double)>{
  'Poblacion': (10.0797, 124.3431),
  'Banlasan': (10.0912, 124.3315),
  'Bongbong': (10.0664, 124.3562),
  'Catoogan': (10.0885, 124.3541),
  'Guinobatan': (10.0711, 124.3302),
  'Hinlayagan Ilaud': (10.0542, 124.3611),
  'Hinlayagan Ilaya': (10.0461, 124.3698),
  'Kauswagan': (10.1023, 124.3389),
  'Kinan-oan': (10.0589, 124.3233),
  'La Union': (10.1102, 124.3211),
  'La Victoria': (10.0638, 124.3371),
  'Mabuhay Cabigohan': (10.0958, 124.3628),
  'Mahagbu': (10.0521, 124.3455),
  'Manuel M. Roxas': (10.0871, 124.3168),
  'San Isidro': (10.1108, 124.3542),
  'San Vicente': (10.0703, 124.3634),
  'Santo Tomas': (10.0944, 124.3462),
  'Soom': (10.0497, 124.3311),
  'Tagum Norte': (10.1161, 124.3342),
  'Tagum Sur': (10.0621, 124.3519),
};

/// Coordinates for a barangay, falling back to a stable pseudo-offset around
/// the municipal centre for any value the registry does not know yet.
(double, double) coordinatesForBarangay(String barangay) {
  final known = barangayCoordinates[barangay];
  if (known != null) return known;
  var seed = 0;
  for (final code in barangay.codeUnits) {
    seed = (seed * 31 + code) & 0xFFFF;
  }
  final lat = trinidadCenter.lat + ((seed % 100) - 50) / 12000.0;
  final lng = trinidadCenter.lng + (((seed >> 3) % 100) - 50) / 12000.0;
  return (lat, lng);
}

/// Great-circle distance in kilometres between two lat/lng points (haversine).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371.0;
  double rad(double deg) => deg * pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * earthRadius * asin(sqrt(a.toDouble()));
}

/// Whether [value] is a purok/sitio the API will accept.
///
/// Mirrors App\Support\Puroks on the server: the value must open with the
/// designation "Purok" or "Sitio" — in any casing — followed by a name, may
/// contain Unicode letters (so real names such as "Sitio Peña" or
/// "Sitio Sto. Niño" pass), and must not carry municipal scope. Checking here
/// saves a member a round trip that would only answer 422.
bool isValidPurokSitio(String value) {
  final v = value.trim();
  if (v.length < 3 || v.length > 60) return false;
  final designation =
      RegExp(r'^(purok|sitio)\s+\S', caseSensitive: false, unicode: true);
  if (!designation.hasMatch(v)) return false;
  final municipalScope = RegExp(
    r'barangay|trinidad|bohol|municipal|city|province',
    caseSensitive: false,
  );
  return !municipalScope.hasMatch(v);
}

/// Fold user input into the canonical form the API stores, so the client can
/// echo "Purok 3" however the member typed it ("purok  3", "PUROK 3",
/// "Purok3"). The name after the designation is left as typed.
String canonicalizePurokSitio(String value) {
  var v = value.replaceAll(RegExp(r'[\s\u00A0\u202F]+'), ' ').trim();
  if (v.isEmpty) return v;
  // Re-attach a dropped separator ("Purok3"), then restore the designation's
  // proper casing.
  v = v.replaceFirstMapped(
    RegExp(r'^(purok|sitio)(?=[\p{L}\p{N}])', caseSensitive: false, unicode: true),
    (m) => '${m[1]} ',
  );
  return v.replaceFirstMapped(
    RegExp(r'^(purok|sitio)\b', caseSensitive: false, unicode: true),
    (m) => m[1]![0].toUpperCase() + m[1]!.substring(1).toLowerCase(),
  );
}

