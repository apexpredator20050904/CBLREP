import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/core/listing_draft_store.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';

/// Phase 4 — an unfinished listing is kept on the device and offered back.
///
/// Posting is a multi-field task that gets interrupted; losing the form to a
/// back-swipe stops people posting. These tests cover the client half: a draft
/// is restored on open, autosaved while typing, cleared on discard, and scoped
/// per member so two people on one phone do not inherit each other's drafts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const member = UserModel(
    id: 42,
    name: 'Member',
    email: 'member@example.test',
    barangay: 'Bongbong',
    purokSitio: 'Purok 3',
    verified: true,
    verificationStatus: 'Verified',
  );

  Widget host({UserModel user = member}) => MultiProvider(
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

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the store round-trips a draft for one member only', () async {
    await ListingDraftStore.save(42, {'title': 'A drill', 'barangay': 'Bongbong'});
    final loaded = await ListingDraftStore.load(42);
    expect(loaded?['title'], 'A drill');

    // Another member on the same phone sees nothing.
    expect(await ListingDraftStore.load(7), isNull);

    await ListingDraftStore.clear(42);
    expect(await ListingDraftStore.load(42), isNull);
  });

  testWidgets('a saved draft is restored into the form', (tester) async {
    await ListingDraftStore.save(42, {
      'title': 'A second-hand bike',
      'description': 'Gears slip on the third cog.',
      'barangay': 'Bongbong',
      'purok': 'Purok 3',
      'category': 'Electronics',
      'compensation': 'paid',
      'price': '1500',
      'priceNegotiable': true,
    });

    useTallSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('A second-hand bike'), findsOneWidget);
    expect(find.text('Gears slip on the third cog.'), findsOneWidget);
    expect(find.text('1500'), findsOneWidget);
    expect(find.text('We saved your unfinished draft. Pick up where you left off.'),
        findsOneWidget);
  });

  testWidgets('a structured need draft restores its unit and urgency',
      (tester) async {
    await ListingDraftStore.save(42, {
      'title': 'Rice',
      'type': 'request',
      'compensation': 'barter',
      'quantityValue': '2.5',
      'quantityUnit': 'sack',
      'urgency': 'urgent',
      'barangay': 'Bongbong',
      'purok': 'Purok 3',
      'category': 'Food',
    });

    useTallSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'sacks')).selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Urgent / Today'))
          .selected,
      isTrue,
    );
  });

  testWidgets('typing autosaves the draft', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'What are you offering?'),
      'Fresh mangoes',
    );
    // Let the 700ms debounce elapse, then let the async write settle.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    final draft = await ListingDraftStore.load(42);
    expect(draft?['title'], 'Fresh mangoes');
  });

  testWidgets('discarding clears the draft and the form', (tester) async {
    await ListingDraftStore.save(42, {'title': 'Discard me'});

    useTallSurface(tester);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Discard me'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard me'), findsNothing);
    expect(await ListingDraftStore.load(42), isNull);
  });
}
