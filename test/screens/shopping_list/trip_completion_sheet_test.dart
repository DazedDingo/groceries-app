import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/history_entry.dart';
import 'package:groceries_app/screens/shopping_list/widgets/trip_completion_sheet.dart';

HistoryEntry _entry({
  required String id,
  required String name,
  required HistoryAction action,
  required DateTime at,
  String by = 'Alice',
  int qty = 1,
}) =>
    HistoryEntry(
      id: id,
      itemName: name,
      categoryId: 'c',
      action: action,
      quantity: qty,
      at: at,
      byName: by,
    );

void main() {
  group('computeTripStats', () {
    final now = DateTime(2026, 4, 17, 18, 0);

    test('returns null for empty history', () {
      final stats = computeTripStats(
        history: [],
        now: now,
        firstOfDay: false,
      );
      expect(stats, isNull);
    });

    test('returns null when history has no bought entries', () {
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'apple', action: HistoryAction.added, at: now),
          _entry(id: '2', name: 'apple', action: HistoryAction.deleted, at: now),
        ],
        now: now,
        firstOfDay: false,
      );
      expect(stats, isNull);
    });

    test('counts bought entries inside the trip window', () {
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'milk', action: HistoryAction.bought,
              at: now.subtract(const Duration(minutes: 10))),
          _entry(id: '2', name: 'eggs', action: HistoryAction.bought,
              at: now.subtract(const Duration(minutes: 30))),
          _entry(id: '3', name: 'bread', action: HistoryAction.bought,
              at: now.subtract(const Duration(minutes: 45))),
        ],
        now: now,
        firstOfDay: false,
      );
      expect(stats, isNotNull);
      expect(stats!.itemCount, 3);
      expect(stats.duration, const Duration(minutes: 35));
    });

    test('excludes bought entries outside window', () {
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'recent',
              action: HistoryAction.bought,
              at: now.subtract(const Duration(minutes: 5))),
          _entry(id: '2', name: 'old',
              action: HistoryAction.bought,
              at: now.subtract(const Duration(hours: 8))),
        ],
        now: now,
        firstOfDay: false,
        tripWindow: const Duration(hours: 4),
      );
      expect(stats!.itemCount, 1);
      expect(stats.perPerson, {'Alice': 1});
    });

    test('excludes non-bought actions', () {
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'bought',
              action: HistoryAction.bought, at: now),
          _entry(id: '2', name: 'added',
              action: HistoryAction.added, at: now),
          _entry(id: '3', name: 'deleted',
              action: HistoryAction.deleted, at: now),
        ],
        now: now,
        firstOfDay: false,
      );
      expect(stats!.itemCount, 1);
    });

    test('groups per-person contributions', () {
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'x', action: HistoryAction.bought, at: now, by: 'Alice'),
          _entry(id: '2', name: 'y', action: HistoryAction.bought, at: now, by: 'Alice'),
          _entry(id: '3', name: 'z', action: HistoryAction.bought, at: now, by: 'Bob'),
        ],
        now: now,
        firstOfDay: false,
      );
      expect(stats!.perPerson, {'Alice': 2, 'Bob': 1});
    });

    test('passes firstOfDay through', () {
      final stats = computeTripStats(
        history: [_entry(id: '1', name: 'x', action: HistoryAction.bought, at: now)],
        now: now,
        firstOfDay: true,
      );
      expect(stats!.firstOfDay, isTrue);
    });

    test('single item gives zero duration', () {
      final stats = computeTripStats(
        history: [_entry(id: '1', name: 'x', action: HistoryAction.bought, at: now)],
        now: now,
        firstOfDay: false,
      );
      expect(stats!.duration, Duration.zero);
    });

    test('window edge: exactly at boundary counted inclusive', () {
      final boundary = now.subtract(const Duration(hours: 4));
      final stats = computeTripStats(
        history: [
          _entry(id: '1', name: 'latest',
              action: HistoryAction.bought, at: now),
          _entry(id: '2', name: 'boundary',
              action: HistoryAction.bought, at: boundary),
        ],
        now: now,
        firstOfDay: false,
        tripWindow: const Duration(hours: 4),
      );
      expect(stats!.itemCount, 2);
    });
  });

  group('formatTripDuration', () {
    test('under a minute renders as "moments"', () {
      expect(formatTripDuration(const Duration(seconds: 30)), 'moments');
      expect(formatTripDuration(Duration.zero), 'moments');
    });

    test('minutes render as "N min"', () {
      expect(formatTripDuration(const Duration(minutes: 5)), '5 min');
      expect(formatTripDuration(const Duration(minutes: 59)), '59 min');
    });

    test('whole hours render as "N h"', () {
      expect(formatTripDuration(const Duration(hours: 1)), '1 h');
      expect(formatTripDuration(const Duration(hours: 3)), '3 h');
    });

    test('hours + minutes render as "Nh Mm"', () {
      expect(formatTripDuration(const Duration(hours: 1, minutes: 20)), '1h 20m');
      expect(formatTripDuration(const Duration(hours: 2, minutes: 5)), '2h 5m');
    });
  });
}
