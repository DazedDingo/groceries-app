import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/below_optimal_promoter.dart';

PantryItem _p({
  String id = 'p1',
  String name = 'garlic',
  required int optimal,
  required int current,
}) =>
    PantryItem(
      id: id,
      name: name,
      categoryId: 'cat',
      preferredStores: const [],
      optimalQuantity: optimal,
      currentQuantity: current,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
    );

ShoppingItem _s({
  String id = 's1',
  String name = 'garlic',
  String? pantryItemId,
}) =>
    ShoppingItem(
      id: id,
      name: name,
      quantity: 1,
      categoryId: 'cat',
      preferredStores: const [],
      pantryItemId: pantryItemId,
      recipeSource: null,
      isRecurring: false,
      addedBy: const AddedBy(
        uid: 'u', displayName: 'X', source: ItemSource.app,
      ),
      addedAt: DateTime(2026, 4, 30),
    );

void main() {
  group('decideBelowOptimalAutoAdd', () {
    test('garlic: optimal 1, current 1 → 0, list empty: ADD qty 1', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 1, current: 1),
        priorCurrent: 1,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isTrue, reason: r.reasonSkipped);
      expect(r.qtyToAdd, 1);
    });

    test('optimal 2, current 2 → 1, list empty: ADD qty 1', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 2, current: 2),
        priorCurrent: 2,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isTrue);
      expect(r.qtyToAdd, 1);
    });

    test('optimal 3, current 3 → 2, list empty: ADD qty 1', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 3, current: 3),
        priorCurrent: 3,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isTrue);
      expect(r.qtyToAdd, 1);
    });

    test('above optimal: optimal 1, current 3 → 2: SKIP (still above)', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 1, current: 3),
        priorCurrent: 3,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isFalse);
    });

    test('already below optimal: optimal 2, current 1 → 0: SKIP (no cross)', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 2, current: 1),
        priorCurrent: 1,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isFalse);
    });

    test('skip when same pantryItemId already on list', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(id: 'pg', optimal: 1, current: 1),
        priorCurrent: 1,
        shoppingList: [_s(pantryItemId: 'pg')],
      );
      expect(r.shouldAdd, isFalse);
      expect(r.reasonSkipped, contains('already'));
    });

    test('skip when same name (case-insensitive) is on list, even without pantryItemId', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 1, current: 1, name: 'Garlic'),
        priorCurrent: 1,
        shoppingList: [_s(name: 'GARLIC', pantryItemId: null)],
      );
      expect(r.shouldAdd, isFalse);
    });

    test('different name on list does NOT block add', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 1, current: 1, name: 'garlic'),
        priorCurrent: 1,
        shoppingList: [_s(name: 'onion', pantryItemId: null)],
      );
      expect(r.shouldAdd, isTrue);
    });

    test('optimal 0 → SKIP (item is intentionally untracked)', () {
      final r = decideBelowOptimalAutoAdd(
        item: _p(optimal: 0, current: 1),
        priorCurrent: 1,
        shoppingList: const [],
      );
      expect(r.shouldAdd, isFalse);
    });
  });
}
