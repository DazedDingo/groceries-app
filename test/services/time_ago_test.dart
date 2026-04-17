import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/services/time_ago.dart';

final _now = DateTime(2026, 4, 17, 12);

void main() {
  group('timeAgo', () {
    test('future / clock-skew returns "just now"', () {
      expect(
        timeAgo(_now.add(const Duration(seconds: 10)), now: _now),
        'just now',
      );
    });

    test('within 45 seconds → "just now"', () {
      expect(timeAgo(_now.subtract(const Duration(seconds: 30)), now: _now),
          'just now');
    });

    test('1 minute → "1 min ago"', () {
      expect(timeAgo(_now.subtract(const Duration(minutes: 1)), now: _now),
          '1 min ago');
    });

    test('5 minutes → "5 min ago"', () {
      expect(timeAgo(_now.subtract(const Duration(minutes: 5)), now: _now),
          '5 min ago');
    });

    test('59 minutes → "59 min ago"', () {
      expect(timeAgo(_now.subtract(const Duration(minutes: 59)), now: _now),
          '59 min ago');
    });

    test('1 hour → "1 hour ago"', () {
      expect(timeAgo(_now.subtract(const Duration(hours: 1)), now: _now),
          '1 hour ago');
    });

    test('5 hours → "5 hours ago"', () {
      expect(timeAgo(_now.subtract(const Duration(hours: 5)), now: _now),
          '5 hours ago');
    });

    test('1 day → "yesterday"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 1)), now: _now),
          'yesterday');
    });

    test('3 days → "3 days ago"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 3)), now: _now),
          '3 days ago');
    });

    test('35 days → "1 month ago"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 35)), now: _now),
          '1 month ago');
    });

    test('100 days → "3 months ago"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 100)), now: _now),
          '3 months ago');
    });

    test('400 days → "1 year ago"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 400)), now: _now),
          '1 year ago');
    });

    test('800 days → "2 years ago"', () {
      expect(timeAgo(_now.subtract(const Duration(days: 800)), now: _now),
          '2 years ago');
    });
  });
}
