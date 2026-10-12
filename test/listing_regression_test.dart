import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/listing_card.dart';

/// Guards the two defects these tests were written for, so they cannot come
/// back unnoticed:
///
///  1. A location chip whose label is not bounded (the old
///     `Row(mainAxisSize: min)` + unbounded `Text`) overflows as soon as the
///     text exceeds the available width.
///  2. The card image was a fixed 140px inside a grid cell that shrinks on
///     narrow devices, which clipped the body and produced a `RenderFlex
///     overflowed` stripe.
ListingModel _listing({String title = 'Item', String purok = 'Purok 3'}) =>
    ListingModel(
      id: 1,
      title: title,
      description: 'desc',
      category: 'Tools',
      condition: 'Good',
      location: 'Poblacion, $purok',
      barangay: 'Poblacion',
      purokSitio: purok,
      owner: 'Juan Dela Cruz',
      ownerId: 2,
      type: 'offer',
      compensationType: 'barter',
      compensationLabel: 'BARTER',
      active: true,
    );

void main() {
  group('ListingCard regressions', () {
    testWidgets('bare-bones card renders inside a very small cell',
        (tester) async {
      // 120dp is narrower than any real grid cell — if this fits, the card's
      // minimum viable box is covered and the grid ratio cannot clip it.
      await tester.pumpWidget(MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 120, height: 200, child: ListingCard(listing: _listing())),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('location chip survives an extremely long purok label',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              height: 220,
              child: ListingCard(
                listing: _listing(
                  title: 'Extremely long listing title that must truncate',
                  purok: 'Purok Poblacion Norte Maliksi Compound Sector 7B',
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LocationChip), findsOneWidget);
    });

    testWidgets('the photo area yields height to the body (not a fixed 140)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 160, height: 260, child: ListingCard(listing: _listing())),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final card = tester.getSize(find.byType(ListingCard));
      // A tall cell must give the extra space to the Flexible image rather
      // than leaving it clipped or overflowing the body.
      expect(card.height, greaterThan(200));
      expect(tester.takeException(), isNull);
    });
  });
}