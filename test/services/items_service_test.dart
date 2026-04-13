import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/services/items_service.dart';
import 'package:groceries_app/models/item.dart';

void main() {
  group('ItemsService', () {
    late ItemsService service;
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = ItemsService(db: fakeDb);
    });

    test('addItem writes to correct collection', () async {
      await service.addItem(
        householdId: 'hh1',
        name: 'Milk',
        categoryId: 'dairy',
        preferredStores: ['tesco'],
        pantryItemId: null,
        addedBy: const AddedBy(uid: 'u1', displayName: 'Alice', source: ItemSource.app),
      );
      final snap = await fakeDb.collection('households/hh1/items').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first['name'], 'Milk');
    });

    test('deleteItem removes document', () async {
      await fakeDb.collection('households/hh1/items').doc('i1').set({
        'name': 'Eggs',
        'quantity': 1,
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': null,
        'addedBy': {'uid': 'u1', 'displayName': 'Alice', 'source': 'app'},
        'addedAt': DateTime.now(),
      });
      final itemSnap = await fakeDb.doc('households/hh1/items/i1').get();
      final item = ShoppingItem.fromFirestore(itemSnap);
      await service.deleteItem(householdId: 'hh1', item: item);
      final snap = await fakeDb.collection('households/hh1/items').get();
      expect(snap.docs, isEmpty);
    });
  });
}
