import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/history_entry.dart';
import 'package:groceries_app/services/shelf_life_learner.dart';

HistoryEntry _h({
  required String name,
  required HistoryAction action,
  required DateTime at,
}) =>
    HistoryEntry(
      id: '$name-${at.millisecondsSinceEpoch}',
      itemName: name,
      categoryId: 'cat',
      action: action,
      quantity: 1,
      at: at,
      byName: 'tester',
    );

void main() {
  group('purchaseDatesFor', () {
    test('extracts bought dates matching item name (case-insensitive)', () {
      final history = [
        _h(name: 'Milk', action: HistoryAction.bought, at: DateTime(2026, 1, 1)),
        _h(name: 'milk', action: HistoryAction.bought, at: DateTime(2026, 1, 8)),
        _h(name: 'MILK', action: HistoryAction.bought, at: DateTime(2026, 1, 15)),
      ];
      final dates = purchaseDatesFor(history, 'milk');
      expect(dates, hasLength(3));
    });

    test('ignores non-bought actions', () {
      final history = [
        _h(name: 'milk', action: HistoryAction.added, at: DateTime(2026, 1, 1)),
        _h(name: 'milk', action: HistoryAction.deleted, at: DateTime(2026, 1, 5)),
        _h(name: 'milk', action: HistoryAction.bought, at: DateTime(2026, 1, 8)),
      ];
      expect(purchaseDatesFor(history, 'milk'), hasLength(1));
    });

    test('ignores other item names', () {
      final history = [
        _h(name: 'milk', action: HistoryAction.bought, at: DateTime(2026, 1, 1)),
        _h(name: 'bread', action: HistoryAction.bought, at: DateTime(2026, 1, 2)),
      ];
      expect(purchaseDatesFor(history, 'milk'), hasLength(1));
    });

    test('empty item name returns empty list', () {
      final history = [
        _h(name: 'milk', action: HistoryAction.bought, at: DateTime(2026, 1, 1)),
      ];
      expect(purchaseDatesFor(history, ''), isEmpty);
      expect(purchaseDatesFor(history, '   '), isEmpty);
    });
  });

  group('learnedShelfLifeDays', () {
    test('returns null for fewer than 3 purchases', () {
      expect(learnedShelfLifeDays([]), isNull);
      expect(learnedShelfLifeDays([DateTime(2026, 1, 1)]), isNull);
      expect(
        learnedShelfLifeDays([DateTime(2026, 1, 1), DateTime(2026, 1, 5)]),
        isNull,
      );
    });

    test('returns median gap for 3+ purchases with consistent cadence', () {
      // 7-day intervals
      final dates = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 22),
      ];
      expect(learnedShelfLifeDays(dates), 7);
    });

    test('median ignores outliers', () {
      // Gaps: 5, 5, 90, 5 → median is 5
      final dates = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 11),
        DateTime(2026, 4, 11), // 90-day gap (holiday? sickness?)
        DateTime(2026, 4, 16),
      ];
      expect(learnedShelfLifeDays(dates), 5);
    });

    test('sorts unsorted input', () {
      final dates = [
        DateTime(2026, 1, 22),
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 15),
        DateTime(2026, 1, 8),
      ];
      expect(learnedShelfLifeDays(dates), 7);
    });

    test('same-day duplicate purchases are discarded (zero-day gaps)', () {
      // Two purchases on same day shouldn't claim a 0-day shelf life.
      final dates = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 15),
      ];
      expect(learnedShelfLifeDays(dates), 7);
    });

    test('even gap count rounds median half-up', () {
      // Gaps: 4, 6 → median = 5
      final dates = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 11),
      ];
      expect(learnedShelfLifeDays(dates), 5);
    });
  });
}
