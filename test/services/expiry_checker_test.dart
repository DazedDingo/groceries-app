import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/expiry_checker.dart';

PantryItem _p({
  required String id,
  required String name,
  int current = 1,
  int optimal = 5,
  DateTime? expiresAt,
}) =>
    PantryItem(
      id: id,
      name: name,
      categoryId: 'dairy',
      preferredStores: const [],
      optimalQuantity: optimal,
      currentQuantity: current,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
      expiresAt: expiresAt,
    );

void main() {
  final now = DateTime(2026, 4, 18, 12);

  group('findExpiringBelowOptimal', () {
    test('flags items that are below optimal AND expired', () {
      final items = [
        _p(id: 'a', name: 'Milk', current: 1, optimal: 3, expiresAt: now.subtract(const Duration(days: 1))),
      ];
      expect(findExpiringBelowOptimal(items, now: now).map((p) => p.id), ['a']);
    });

    test('flags items that are below optimal AND expire within 2 days', () {
      final items = [
        _p(id: 'a', name: 'Yogurt', current: 1, optimal: 3, expiresAt: now.add(const Duration(days: 2))),
        _p(id: 'b', name: 'Cheese', current: 1, optimal: 3, expiresAt: now.add(const Duration(days: 5))),
      ];
      final flagged = findExpiringBelowOptimal(items, now: now).map((p) => p.id).toSet();
      expect(flagged, {'a'});
    });

    test('skips items at or above optimal even if expiring', () {
      final items = [
        _p(id: 'a', name: 'Milk', current: 3, optimal: 3, expiresAt: now.subtract(const Duration(days: 1))),
        _p(id: 'b', name: 'Cream', current: 4, optimal: 3, expiresAt: now.add(const Duration(days: 1))),
      ];
      expect(findExpiringBelowOptimal(items, now: now), isEmpty);
    });

    test('skips items without an expiresAt', () {
      final items = [
        _p(id: 'a', name: 'Flour', current: 0, optimal: 2, expiresAt: null),
      ];
      expect(findExpiringBelowOptimal(items, now: now), isEmpty);
    });
  });

  group('expiringFingerprint', () {
    test('stable across list ordering', () {
      final a = _p(id: 'a', name: 'A', current: 1, optimal: 3, expiresAt: now);
      final b = _p(id: 'b', name: 'B', current: 1, optimal: 3, expiresAt: now);
      expect(expiringFingerprint([a, b]), expiringFingerprint([b, a]));
    });

    test('differs when expiry shifts', () {
      final a1 = _p(id: 'a', name: 'A', current: 1, optimal: 3, expiresAt: now);
      final a2 = _p(id: 'a', name: 'A', current: 1, optimal: 3, expiresAt: now.add(const Duration(days: 1)));
      expect(expiringFingerprint([a1]), isNot(expiringFingerprint([a2])));
    });

    test('differs when a new item joins', () {
      final a = _p(id: 'a', name: 'A', current: 1, optimal: 3, expiresAt: now);
      final b = _p(id: 'b', name: 'B', current: 1, optimal: 3, expiresAt: now);
      expect(expiringFingerprint([a]), isNot(expiringFingerprint([a, b])));
    });
  });
}
