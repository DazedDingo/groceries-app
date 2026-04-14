import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';

void main() {
  group('ShoppingItem', () {
    test('round-trips through Firestore map', () {
      final item = ShoppingItem(
        id: 'i1',
        name: 'Milk',
        quantity: 2,
        categoryId: 'dairy',
        preferredStores: ['tesco'],
        pantryItemId: null,
        isRecurring: true,
        addedBy: const AddedBy(uid: 'u1', displayName: 'Alice', source: ItemSource.app),
        addedAt: DateTime(2026, 4, 11),
      );
      final map = item.toMap();
      expect(map['name'], 'Milk');
      expect(map['quantity'], 2);
      expect(map['addedBy']['source'], 'app');
      expect(map['isRecurring'], true);
    });

    test('isRecurring defaults to false', () {
      final item = ShoppingItem(
        id: 'i2',
        name: 'Eggs',
        quantity: 1,
        categoryId: 'dairy',
        preferredStores: [],
        pantryItemId: null,
        addedBy: const AddedBy(uid: 'u1', displayName: 'Alice', source: ItemSource.app),
        addedAt: DateTime(2026, 4, 11),
      );
      expect(item.isRecurring, false);
      expect(item.toMap()['isRecurring'], false);
    });
  });
}
