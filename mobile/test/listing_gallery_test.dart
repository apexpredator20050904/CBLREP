import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/create_listing_screen.dart';
import 'package:untitled1/screens/listing_detail_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// Phase 4 — multi-photo listings.
///
/// The backend returns an ordered `image_urls` gallery with `image_url` as the
/// cover. The model keeps both in step, and the detail screen turns several
/// photos into a swipeable pager so a buyer can judge an item's condition.
void main() {
  ListingModel listing({List<String> images = const []}) => ListingModel(
        id: 1,
        title: 'A rice cooker',
        description: 'Works fine.',
        category: 'Electronics',
        condition: 'Good',
        location: 'Poblacion, Purok 3',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        owner: 'Maria',
        ownerId: 7,
        type: 'offer',
        compensationType: 'free',
        compensationLabel: 'FREE SHARING',
        active: true,
        imageUrl: images.isEmpty ? null : images.first,
        imageUrls: images,
      );

  Widget host(Widget child, {UserModel? user}) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(ApiService.instance)..user = user,
          ),
          ChangeNotifierProvider(
            create: (_) => ListingsProvider(ApiService.instance),
          ),
        ],
        child: MaterialApp(theme: CblrepTheme.lightCream, home: child),
      );

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  test('the model keeps the gallery and the cover in step', () {
    final three = ListingModel.fromJson({
      'id': 1,
      'title': 'x',
      'image_url': 'https://example.test/storage/listing-images/a.jpg',
      'image_urls': [
        'https://example.test/storage/listing-images/a.jpg',
        'https://example.test/storage/listing-images/b.jpg',
      ],
    });
    expect(three.imageUrls, hasLength(2));
    expect(three.imageUrl, three.imageUrls.first);

    // An older payload with only the single cover still yields a one-photo
    // gallery, so the detail screen renders it.
    final legacy = ListingModel.fromJson({
      'id': 2,
      'title': 'y',
      'image_url': 'https://example.test/storage/listing-images/only.jpg',
    });
    expect(legacy.imageUrls, hasLength(1));
    expect(legacy.imageUrls.first, legacy.imageUrl);

    final none = ListingModel.fromJson({'id': 3, 'title': 'z'});
    expect(none.imageUrls, isEmpty);
  });

  testWidgets('a multi-photo listing gets a swipeable pager', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(ListingDetailScreen(
      listing: listing(images: const [
        'https://example.test/a.jpg',
        'https://example.test/b.jpg',
        'https://example.test/c.jpg',
      ]),
    )));
    await tester.pumpAndSettle();

    // Position badge names the current page and the total.
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('a single-photo listing shows no pager badge', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(ListingDetailScreen(
      listing: listing(images: const ['https://example.test/a.jpg']),
    )));
    await tester.pumpAndSettle();

    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('the Post form advertises the photo gallery', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(host(
      const CreateListingScreen(),
      user: const UserModel(
        id: 1,
        name: 'Member',
        email: 'm@example.test',
        barangay: 'Bongbong',
        purokSitio: 'Purok 3',
        verified: true,
        verificationStatus: 'Verified',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Add item photos (optional)'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });
}
