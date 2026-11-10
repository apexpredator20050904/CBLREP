import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/core/feedback.dart';

/// The confirmation dialog's dismiss action must be renameable. Cancelling an
/// exchange needs "Back" so it cannot be mistaken for the "Cancel exchange"
/// action it sits beside.
void main() {
  testWidgets('a custom dismiss label sits beside the confirm action',
      (tester) async {
    bool? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Feedback.confirm(
                  context,
                  title: 'Cancel exchange?',
                  message: 'This cancels "Rice" for both members.',
                  confirmLabel: 'Cancel exchange',
                  cancelLabel: 'Back',
                  danger: true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Cancel exchange'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(result, isFalse,
        reason: 'Back must dismiss the dialog without cancelling anything.');
  });
}
