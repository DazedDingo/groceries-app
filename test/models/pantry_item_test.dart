import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/pantry_item.dart';

void main() {
  group('PantryItem', () {
    test('isBelowOptimal returns true when current < optimal', () {
      const item = PantryItem(
        id: 'p1', name: 'Eggs', categoryId: 'dairy',
        preferredStores: [], optimalQuantity: 6,
        currentQuantity: 2, restockAfterDays: 7,
        lastNudgedAt: null, lastPurchasedAt: null,
      );
      expect(item.isBelowOptimal, isTrue);
    });
  });
}
