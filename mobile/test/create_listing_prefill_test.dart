import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';

/// Phase 4 — the Post form is prefilled from the member's saved location, so a
/// member posting from home does not retype their barangay/purok every time.
///
/// Only values the API would accept are used, so a legacy or unusual profile
/// cannot seed the form with something it would then reject on submit.
void main() {
  UserModel member({
    String barangay = 'Bongbong',
    String purok = 'Purok 7',
  }) =>
      UserModel(
        id: 1,
        name: 'Member',
        email: 'member@example.test',
        barangay: barangay,
        purokSitio: purok,
        verified: true,
        verificationStatus: 'Verified',
      );

  Widget host(UserModel user) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(ApiService.instance)..user = user,
          ),
          ChangeNotifierProvider(
            create: (_) => ListingsProvider(ApiService.instance),
          ),
        ],
        child: const MaterialApp(home: CreateListingScreen()),
      );

  // The form is a lazy ListView; the location fields sit below the fold on the
  // default 800x600 surface, so give it room to build them.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('seeds barangay and purok from the profile', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(member()));
    await tester.pumpAndSettle();

    expect(find.text('Bongbong'), findsOneWidget);
    expect(find.text('Purok 7'), findsOneWidget);
  });

  testWidgets('ignores a profile location the API would reject', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      host(member(barangay: 'Cebu City', purok: '123 Main Street')),
    );
    await tester.pumpAndSettle();

    // Falls back to the first valid barangay and leaves purok empty.
    expect(find.text('Poblacion'), findsOneWidget);
    expect(find.text('123 Main Street'), findsNothing);
  });
}
