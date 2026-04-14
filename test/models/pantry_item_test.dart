import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';

PantryItem _item({
  int optimal = 6,
  int current = 2,
  bool isHighPriority = false,
}) => PantryItem(
  id: 'p1', name: 'Milk', categoryId: 'dairy',
  preferredStores: const [], optimalQuantity: optimal,
  currentQuantity: current, restockAfterDays: 7,
  lastNudgedAt: null, lastPurchasedAt: null,
  isHighPriority: isHighPriority,
);

void main() {
  group('PantryItem', () {
    test('isBelowOptimal returns true when current < optimal', () {
      expect(_item(current: 2, optimal: 6).isBelowOptimal, isTrue);
    });

    test('isBelowOptimal returns false when current == optimal', () {
      expect(_item(current: 6, optimal: 6).isBelowOptimal, isFalse);
    });

    test('isBelowOptimal returns false when current > optimal', () {
      expect(_item(current: 8, optimal: 6).isBelowOptimal, isFalse);
    });

    test('isHighPriority defaults to false', () {
      expect(_item().isHighPriority, isFalse);
    });

    test('isHighPriority true is preserved through copyWith', () {
      final item = _item(isHighPriority: true);
      final copy = item.copyWith();
      expect(copy.isHighPriority, isTrue);
    });

    test('copyWith overrides isHighPriority', () {
      final item = _item(isHighPriority: false);
      final updated = item.copyWith(isHighPriority: true);
      expect(updated.isHighPriority, isTrue);
    });

    test('toMap includes isHighPriority true', () {
      final map = _item(isHighPriority: true).toMap();
      expect(map['isHighPriority'], isTrue);
    });

    test('toMap includes isHighPriority false', () {
      final map = _item(isHighPriority: false).toMap();
      expect(map['isHighPriority'], isFalse);
    });
  });
}
