import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/core/greeting.dart';

/// The English greeting must change with the clock, and the boundaries must
/// stay where the home hero and profile header expect them.
void main() {
  DateTime at(int hour, [int minute = 0]) => DateTime(2026, 1, 1, hour, minute);

  test('morning runs from 05:00 to 11:59', () {
    expect(greetingForNow(at(4, 59)), 'Good evening');
    expect(greetingForNow(at(5)), 'Good morning');
    expect(greetingForNow(at(11, 59)), 'Good morning');
  });

  test('afternoon runs from 12:00 to 17:59', () {
    expect(greetingForNow(at(12)), 'Good afternoon');
    expect(greetingForNow(at(17, 59)), 'Good afternoon');
  });

  test('evening covers 18:00 through midnight', () {
    expect(greetingForNow(at(18)), 'Good evening');
    expect(greetingForNow(at(23, 59)), 'Good evening');
    expect(greetingForNow(at(0)), 'Good evening');
  });
}
