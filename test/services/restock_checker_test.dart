import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/restock_checker.dart';

PantryItem _item({
  int optimal = 5,
  int current = 1,
  int? restockAfterDays = 7,
  DateTime? lastPurchasedAt,
}) => PantryItem(
  id: 'test', name: 'Milk', categoryId: 'dairy',
  preferredStores: const [], optimalQuantity: optimal,
  currentQuantity: current, restockAfterDays: restockAfterDays,
  lastNudgedAt: null, lastPurchasedAt: lastPurchasedAt,
);

void main() {
  group('findOverdueRestocks', () {
    test('returns items below optimal with no purchase date', () {
      final items = [_item(lastPurchasedAt: null)];
      expect(findOverdueRestocks(items), hasLength(1));
    });

    test('returns items past restock interval', () {
      final items = [_item(
        lastPurchasedAt: DateTime.now().subtract(const Duration(days: 10)),
      )];
      expect(findOverdueRestocks(items), hasLength(1));
    });

    test('excludes items purchased recently', () {
      final items = [_item(
        lastPurchasedAt: DateTime.now().subtract(const Duration(days: 2)),
      )];
      expect(findOverdueRestocks(items), isEmpty);
    });

    test('excludes items without restockAfterDays', () {
      final items = [_item(restockAfterDays: null)];
      expect(findOverdueRestocks(items), isEmpty);
    });

    test('excludes items at or above optimal quantity', () {
      final items = [_item(current: 5, optimal: 5)];
      expect(findOverdueRestocks(items), isEmpty);
    });
  });
}
