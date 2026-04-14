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

    Future<ShoppingItem> seedItem({
      String id = 'i1',
      String name = 'Milk',
      int quantity = 1,
      String? pantryItemId,
    }) async {
      await fakeDb.collection('households/hh1/items').doc(id).set({
        'name': name,
        'quantity': quantity,
        'unit': null,
        'note': null,
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': pantryItemId,
        'addedBy': {'uid': 'u1', 'displayName': 'Alice', 'source': 'app'},
        'addedAt': DateTime.now(),
      });
      final snap = await fakeDb.doc('households/hh1/items/$id').get();
      return ShoppingItem.fromFirestore(snap);
    }

    test('checkOff records a "bought" history entry', () async {
      // Powers the "Reorder last trip" UI; if the history row goes missing,
      // the feature silently shows nothing.
      final item = await seedItem(quantity: 2);

      await service.checkOff(householdId: 'hh1', item: item);

      final hist = await fakeDb.collection('households/hh1/history').get();
      expect(hist.docs.length, 1);
      expect(hist.docs.first['action'], 'bought');
      expect(hist.docs.first['itemName'], 'Milk');
      expect(hist.docs.first['quantity'], 2);
    });

    test('updateItem persists summed quantity for the merge flow', () async {
      // Shopping-list "Add to quantity" path calls updateItem with
      // target.quantity + result.quantity. Verifies the primitive that
      // backs the merge-on-duplicate UX.
      await seedItem(quantity: 1);

      await service.updateItem(
        householdId: 'hh1',
        itemId: 'i1',
        name: 'Milk',
        quantity: 1 + 2,
        unit: 'L',
        note: 'organic',
        categoryId: 'dairy',
      );

      final doc = await fakeDb.doc('households/hh1/items/i1').get();
      expect(doc['quantity'], 3);
      expect(doc['unit'], 'L');
      expect(doc['note'], 'organic');
    });
  });
}
