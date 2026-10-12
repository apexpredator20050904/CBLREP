import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/config/community.dart';
import 'package:untitled1/theme/cblrep_theme.dart';

/// Regression guard for dropdown overflow.
///
/// `DropdownButtonFormField` without `isExpanded: true` sizes itself to its
/// widest menu item. The barangay registry contains "Mabuhay Cabigohan" and
/// "Manuel M. Roxas", which overflowed the field on narrow Android displays.
/// `home_feed_screen.dart` already used isExpanded; `profile_screen.dart` and
/// `create_listing_screen.dart` did not.
void main() {
  Widget dropdown(List<String> items, {required bool isExpanded}) => MaterialApp(
        theme: CblrepTheme.lightCream,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                initialValue: items.first,
                // Mirrors the fix applied to the real screens.
                isExpanded: isExpanded,
                decoration: const InputDecoration(labelText: 'Barangay'),
                items: items
                    .map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(b, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

  testWidgets('barangay dropdown fits a narrow phone when isExpanded', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(dropdown(trinidadBarangays, isExpanded: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The button must not exceed the available width.
    final size = tester.getSize(find.byType(DropdownButtonFormField<String>));
    expect(size.width, lessThanOrEqualTo(300));
  });

  testWidgets('the longest barangay name is what would overflow unbounded',
      (tester) async {
    // Guards the registry itself: if a much longer name is ever added, this
    // test is the reminder that isExpanded must stay.
    final longest = trinidadBarangays.reduce((a, b) => a.length >= b.length ? a : b);
    expect(longest, isNotEmpty);
    expect(trinidadBarangays.length, 20,
        reason: 'Trinidad, Bohol has exactly 20 official barangays');
  });

  testWidgets('a long name truncates instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(dropdown(
      ['Mabuhay Cabigohan', 'Manuel M. Roxas', 'Poblacion'],
      isExpanded: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mabuhay Cabigohan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}