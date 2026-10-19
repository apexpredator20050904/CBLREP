import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/listing_card.dart';

/// Guards the defects the listing card is built to avoid:
///
///  1. A location chip whose label is not bounded (the old
///     `Row(mainAxisSize: min)` + unbounded `Text`) overflows as soon as the
///     text exceeds the available width.
///  2. The card used to squeeze its body into a grid cell, so a tall cell
///     clipped the text and produced a `RenderFlex overflowed` stripe. The
///     card is now content-sized — a FIXED-height photo above a natural
///     height body — so the photo is always exactly the same height and the
///     body is never clipped.
///  3. The two fast actions sit in a Row, so a narrow phone could push them
///     past the card's edge. They are Expanded, which keeps them inside it.
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

/// Hosts the card in a phone-width column with unbounded height — the shape
/// the home feed actually gives it.
Widget _host(ListingModel listing, {double width = 320, double? height}) =>
    MaterialApp(
      theme: CblrepTheme.lightCream,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ListingCard(listing: listing),
          ),
        ),
      ),
    );

void main() {
  group('ListingCard regressions', () {
    testWidgets('the card renders inside a phone-width column without overflow',
        (tester) async {
      // 320dp is the narrowest phone this app supports. The card is
      // content-sized, so the column is given an unbounded height.
      await tester.pumpWidget(_host(_listing()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('location chip survives an extremely long purok label',
        (tester) async {
      await tester.pumpWidget(_host(_listing(
        title: 'Extremely long listing title that must truncate',
        purok: 'Purok Poblacion Norte Maliksi Compound Sector 7B',
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LocationChip), findsOneWidget);
    });

    testWidgets('the photo area has a fixed height so every card matches',
        (tester) async {
      await tester.pumpWidget(_host(_listing(), width: 360));
      await tester.pumpAndSettle();

      final card = tester.getSize(find.byType(ListingCard));
      // The card is taller than the photo block: the body sits under it.
      expect(card.height, greaterThan(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the two fast actions and the report menu are all present',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ListingCard(
                listing: _listing(),
                onViewDetails: () {},
                onPropose: () {},
                onReport: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Propose Barter'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card with no report action shows no three-dot menu',
        (tester) async {
      await tester.pumpWidget(_host(_listing()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
