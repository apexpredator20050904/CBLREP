import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/core/api_service.dart';
import 'package:untitled1/models/models.dart';
import 'package:untitled1/providers/auth_provider.dart';
import 'package:untitled1/providers/chat_provider.dart';
import 'package:untitled1/providers/listings_provider.dart';
import 'package:untitled1/screens/chat_screen.dart';
import 'package:untitled1/screens/listing_detail_screen.dart';
import 'package:untitled1/theme/cblrep_theme.dart';
import 'package:untitled1/widgets/member_profile_sheet.dart';

/// The three places a member can report something from.
///
/// A reporting system is only as good as its reach: a member must be able
/// to flag a posting from the feed, a posting from its details page, and a
/// member's account from the profile they are looking at. These tests pin
/// down that every one of those entry points exists — and that the action
/// is NOT offered where it could only fail (your own listing, your own
/// account).
/// A chat provider that never polls, so a test that opens the chat screen
/// does not leave a periodic timer behind.
class _QuietChatProvider extends ChatProvider {
  _QuietChatProvider() : super(ApiService.instance);

  @override
  Future<void> open(int id, {bool live = true}) async {
    conversationId = id;
  }
}

void main() {
  ListingModel _listing({required int ownerId}) => ListingModel(
        id: 1,
        title: 'A borrowed drill',
        description: 'Works fine.',
        category: 'Tools',
        condition: 'Good',
        location: 'Poblacion, Purok 3',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        owner: 'Maria Concepcion',
        ownerId: ownerId,
        ownerVerified: true,
        type: 'offer',
        compensationType: 'barter',
        compensationLabel: 'BARTER',
        active: true,
      );

  UserModel _user(int id) => UserModel(
        id: id,
        name: 'Test Member',
        email: 'member@example.test',
        barangay: 'Poblacion',
        purokSitio: 'Purok 3',
        verified: false,
        verificationStatus: 'Unverified',
      );

  /// A tall surface, so the detail screen's action column is in the tree.
  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('Listing detail report menu', () {
    Widget host(ListingModel listing, UserModel? user) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(ApiService.instance)..user = user,
            ),
            ChangeNotifierProvider<ListingsProvider>(
              create: (_) => ListingsProvider(ApiService.instance),
            ),
          ],
          child: MaterialApp(
            theme: CblrepTheme.lightCream,
            home: ListingDetailScreen(listing: listing),
          ),
        );

    testWidgets('offers report actions to a visitor', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host(_listing(ownerId: 7), _user(99)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Report posting'), findsOneWidget);
      expect(find.text('Report user'), findsOneWidget);
    });

    testWidgets('opens the report sheet for the posting', (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host(_listing(ownerId: 7), _user(99)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report posting'));
      await tester.pumpAndSettle();

      expect(find.text('Report this posting'), findsOneWidget);
      expect(find.text('A borrowed drill'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not offer a report action on your own listing',
        (tester) async {
      await useTallSurface(tester);
      await tester.pumpWidget(host(_listing(ownerId: 7), _user(7)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // The entries are still listed, but greyed out: you cannot report
      // your own posting, and the backend would refuse it.
      final posting = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Report posting'),
      );
      expect(posting.enabled, isFalse);

      final user = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Report user'),
      );
      expect(user.enabled, isFalse);
    });
  });

  group('Member profile sheet', () {
    Widget host({required int userId, required bool canReport}) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(ApiService.instance)..user = _user(99),
            ),
          ],
          child: MaterialApp(
            theme: CblrepTheme.lightCream,
            home: Scaffold(
              body: MemberProfileSheet(
                name: 'Maria Concepcion',
                verified: true,
                barangay: 'Poblacion',
                purokSitio: 'Purok 3',
                userId: userId,
                canReport: canReport,
              ),
            ),
          ),
        );

    testWidgets('shows who the member is', (tester) async {
      await tester.pumpWidget(host(userId: 7, canReport: true));
      await tester.pumpAndSettle();

      expect(find.text('Maria Concepcion'), findsOneWidget);
      expect(find.text('Verified resident'), findsOneWidget);
      expect(find.textContaining('Poblacion'), findsOneWidget);
    });

    testWidgets('offers to report another member', (tester) async {
      await tester.pumpWidget(host(userId: 7, canReport: true));
      await tester.pumpAndSettle();

      expect(find.text('Report this member'), findsOneWidget);
    });

    testWidgets('never offers to report the signed-in member', (tester) async {
      await tester.pumpWidget(host(userId: 99, canReport: false));
      await tester.pumpAndSettle();

      expect(find.text('Report this member'), findsNothing);
      expect(find.text('This is your own account.'), findsOneWidget);
    });
  });

  group('Chat report menu', () {
    testWidgets('offers to report the member in the thread', (tester) async {
      await useTallSurface(tester);

      final chat = _QuietChatProvider()
        ..conversation = {
          'member': {
            'id': 7,
            'name': 'Maria Concepcion',
            'email': 'maria@example.test',
          },
        };

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(ApiService.instance)..user = _user(99),
          ),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ],
        child: MaterialApp(
          theme: CblrepTheme.lightCream,
          home: const ChatScreen(conversationId: 1, title: 'Maria Concepcion'),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Report user'), findsOneWidget);
    });
  });
}
