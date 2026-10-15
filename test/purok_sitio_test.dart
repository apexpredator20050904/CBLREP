import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/config/community.dart';

/// Client half of the purok/sitio rule. The server (App\Support\Puroks) is the
/// authority; these checks exist so a member is corrected in-line instead of
/// after a 422 round trip, so the two must agree on the obvious cases.
void main() {
  group('isValidPurokSitio', () {
    test('accepts the designation in any casing', () {
      expect(isValidPurokSitio('Purok 3'), isTrue);
      expect(isValidPurokSitio('purok 3'), isTrue);
      expect(isValidPurokSitio('PUROK 3'), isTrue);
      expect(isValidPurokSitio('Sitio Cadapdapan'), isTrue);
      expect(isValidPurokSitio('sitio Cadapdapan'), isTrue);
      expect(isValidPurokSitio('  Purok 3  '), isTrue);
    });

    test('accepts Unicode letters in real place names', () {
      expect(isValidPurokSitio('Sitio Peña'), isTrue);
      expect(isValidPurokSitio('Sitio Cañada'), isTrue);
      expect(isValidPurokSitio('Sitio Sto. Niño'), isTrue);
    });

    test('rejects a missing designation or municipal scope', () {
      expect(isValidPurokSitio(''), isFalse);
      expect(isValidPurokSitio('3'), isFalse);
      expect(isValidPurokSitio('Barangay Poblacion'), isFalse);
      expect(isValidPurokSitio('Purok 3, Trinidad, Bohol'), isFalse);
      expect(isValidPurokSitio('Purok'), isFalse);
    });
  });

  group('canonicalizePurokSitio', () {
    test('restores designation casing and collapses spacing', () {
      expect(canonicalizePurokSitio('purok 3'), 'Purok 3');
      expect(canonicalizePurokSitio('PUROK  3'), 'Purok 3');
      expect(canonicalizePurokSitio('Purok3'), 'Purok 3');
      expect(canonicalizePurokSitio('  sitio   Cadapdapan '), 'Sitio Cadapdapan');
    });

    test('leaves the name after the designation as typed', () {
      expect(canonicalizePurokSitio('purok III'), 'Purok III');
      expect(canonicalizePurokSitio('sitio Sto. Niño'), 'Sitio Sto. Niño');
    });
  });
}
