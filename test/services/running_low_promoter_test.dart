import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/running_low_promoter.dart';

PantryItem _pantry({
  required String id,
  DateTime? runningLowAt,
  int optimal = 2,
  int current = 1,
}) =>
    PantryItem(
      id: id,
      name: id,
      categoryId: 'c',
      preferredStores: const [],
      optimalQuantity: optimal,
      currentQuantity: current,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
      runningLowAt: runningLowAt,
    );

ShoppingItem _shopping({required String id, String? pantryItemId}) =>
    ShoppingItem(
      id: id,
      name: id,
      quantity: 1,
      categoryId: 'c',
      preferredStores: const [],
      pantryItemId: pantryItemId,
      addedBy: const AddedBy(
        uid: null, displayName: 'test', source: ItemSource.app,
      ),
      addedAt: DateTime(2026, 4, 18),
    );

void main() {
  group('itemsDueForPromotion', () {
    final now = DateTime(2026, 4, 18, 12);

    test('returns items flagged ≥ delay ago', () {
      final p = _pantry(
        id: 'p1', runningLowAt: now.subtract(const Duration(days: 2)),
      );
      final due = itemsDueForPromotion(
        pantry: [p], shoppingList: const [], now: now,
      );
      expect(due.map((i) => i.id), ['p1']);
    });

    test('skips items flagged less than delay ago', () {
      final p = _pantry(
        id: 'p1',
        runningLowAt: now.subtract(const Duration(days: 1, hours: 23)),
      );
      final due = itemsDueForPromotion(
        pantry: [p], shoppingList: const [], now: now,
      );
      expect(due, isEmpty);
    });

    test('skips unflagged items', () {
      final p = _pantry(id: 'p1', runningLowAt: null);
      final due = itemsDueForPromotion(
        pantry: [p], shoppingList: const [], now: now,
      );
      expect(due, isEmpty);
    });

    test('skips items already on the shopping list', () {
      final p = _pantry(
        id: 'p1', runningLowAt: now.subtract(const Duration(days: 5)),
      );
      final s = _shopping(id: 's1', pantryItemId: 'p1');
      final due = itemsDueForPromotion(
        pantry: [p], shoppingList: [s], now: now,
      );
      expect(due, isEmpty);
    });

    test('still promotes items whose pantryItemId appears unlinked', () {
      // Shopping list has an item with a DIFFERENT pantryItemId — shouldn't
      // block promotion of p1.
      final p = _pantry(
        id: 'p1', runningLowAt: now.subtract(const Duration(days: 3)),
      );
      final s = _shopping(id: 's1', pantryItemId: 'pX');
      final due = itemsDueForPromotion(
        pantry: [p], shoppingList: [s], now: now,
      );
      expect(due.map((i) => i.id), ['p1']);
    });

    test('custom delay overrides default', () {
      final p = _pantry(
        id: 'p1', runningLowAt: now.subtract(const Duration(days: 1)),
      );
      final due = itemsDueForPromotion(
        pantry: [p],
        shoppingList: const [],
        now: now,
        delay: const Duration(hours: 12),
      );
      expect(due.map((i) => i.id), ['p1']);
    });

    test('returns multiple due items', () {
      final p1 = _pantry(
        id: 'p1', runningLowAt: now.subtract(const Duration(days: 3)),
      );
      final p2 = _pantry(
        id: 'p2', runningLowAt: now.subtract(const Duration(days: 5)),
      );
      final p3 = _pantry(
        id: 'p3', runningLowAt: now.subtract(const Duration(hours: 6)),
      );
      final due = itemsDueForPromotion(
        pantry: [p1, p2, p3], shoppingList: const [], now: now,
      );
      expect(due.map((i) => i.id).toSet(), {'p1', 'p2'});
    });
  });

  group('promoteQuantities', () {
    test('decrements current by 1 and adds (optimal - newCurrent) to list', () {
      final p = _pantry(id: 'p1', optimal: 5, current: 3);
      final q = promoteQuantities(p);
      expect(q.newCurrent, 2);
      // Check-off will add 3 back → lands at optimal (5).
      expect(q.listQuantity, 3);
    });

    test('clamps current at 0 — never negative', () {
      final p = _pantry(id: 'p1', optimal: 5, current: 0);
      final q = promoteQuantities(p);
      expect(q.newCurrent, 0);
      expect(q.listQuantity, 5);
    });

    test('handles single-container items (optimal=1, current=1)', () {
      // One shaker of cinnamon: flagged low → pantry drops to 0, list gets 1.
      final p = _pantry(id: 'p1', optimal: 1, current: 1);
      final q = promoteQuantities(p);
      expect(q.newCurrent, 0);
      expect(q.listQuantity, 1);
    });

    test('listQuantity never drops below 1 even if already at/above optimal', () {
      // Shouldn't happen in practice (why flag running-low at optimal?), but
      // the clamp is load-bearing: post-decrement current of `optimal` would
      // make listQuantity = 0 without it.
      final p = _pantry(id: 'p1', optimal: 2, current: 3);
      final q = promoteQuantities(p);
      expect(q.newCurrent, 2);
      expect(q.listQuantity, 1);
    });
  });
}
