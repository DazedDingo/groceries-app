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

    test('addItems writes all items + history entries in one batch', () async {
      const addedBy = AddedBy(
        uid: 'u1', displayName: 'Alice', source: ItemSource.voiceInApp,
      );
      await service.addItems(
        householdId: 'hh1',
        items: const [
          (name: 'milk', categoryId: 'dairy', quantity: 1, unit: null),
          (name: 'flour', categoryId: 'baking', quantity: 2, unit: 'kg'),
          (name: 'eggs', categoryId: 'dairy', quantity: 12, unit: null),
        ],
        addedBy: addedBy,
      );

      final items = await fakeDb.collection('households/hh1/items').get();
      expect(items.docs.length, 3);
      final names = items.docs.map((d) => d['name']).toSet();
      expect(names, {'milk', 'flour', 'eggs'});
      final flour = items.docs.firstWhere((d) => d['name'] == 'flour');
      expect(flour['unit'], 'kg');
      expect(flour['quantity'], 2);

      final hist = await fakeDb.collection('households/hh1/history').get();
      expect(hist.docs.length, 3,
          reason: 'each addItems entry should also create a history record');
      expect(hist.docs.every((d) => d['action'] == 'added'), isTrue);
    });

    test('addItems preserves unit field per item (mixed null/non-null)',
        () async {
      const addedBy = AddedBy(
        uid: 'u1', displayName: 'Alice', source: ItemSource.voiceInApp,
      );
      await service.addItems(
        householdId: 'hh1',
        items: const [
          (name: 'apples', categoryId: 'produce', quantity: 6, unit: null),
          (name: 'flour', categoryId: 'baking', quantity: 1, unit: 'kg'),
        ],
        addedBy: addedBy,
      );
      final items = await fakeDb.collection('households/hh1/items').get();
      final apples = items.docs.firstWhere((d) => d['name'] == 'apples');
      final flour = items.docs.firstWhere((d) => d['name'] == 'flour');
      expect(apples['unit'], isNull);
      expect(flour['unit'], 'kg');
    });

    test('addItems records correct attribution and addedAt timestamp',
        () async {
      const addedBy = AddedBy(
        uid: 'u1', displayName: 'Bob Smith', source: ItemSource.voiceInApp,
      );
      await service.addItems(
        householdId: 'hh1',
        items: const [
          (name: 'rice', categoryId: 'pantry', quantity: 1, unit: null),
        ],
        addedBy: addedBy,
      );
      final items = await fakeDb.collection('households/hh1/items').get();
      final rice = items.docs.first;
      expect((rice['addedBy'] as Map)['displayName'], 'Bob Smith');
      expect((rice['addedBy'] as Map)['uid'], 'u1');
      expect((rice['addedBy'] as Map)['source'], 'voice_in_app');
      expect(rice['addedAt'], isNotNull);

      final hist = await fakeDb.collection('households/hh1/history').get();
      expect(hist.docs.first['byName'], 'Bob Smith');
    });

    test('addItems isolates writes per household', () async {
      const addedBy = AddedBy(
        uid: 'u1', displayName: 'Alice', source: ItemSource.app,
      );
      await service.addItems(
        householdId: 'hh1',
        items: const [
          (name: 'milk', categoryId: 'dairy', quantity: 1, unit: null),
        ],
        addedBy: addedBy,
      );
      await service.addItems(
        householdId: 'hh2',
        items: const [
          (name: 'eggs', categoryId: 'dairy', quantity: 12, unit: null),
        ],
        addedBy: addedBy,
      );
      final hh1 = await fakeDb.collection('households/hh1/items').get();
      final hh2 = await fakeDb.collection('households/hh2/items').get();
      expect(hh1.docs.map((d) => d['name']).toList(), ['milk']);
      expect(hh2.docs.map((d) => d['name']).toList(), ['eggs']);
    });

    test('addItems with empty list is a no-op', () async {
      const addedBy = AddedBy(
        uid: 'u1', displayName: 'Alice', source: ItemSource.app,
      );
      await service.addItems(
        householdId: 'hh1',
        items: const [],
        addedBy: addedBy,
      );
      final items = await fakeDb.collection('households/hh1/items').get();
      expect(items.docs, isEmpty);
    });

    test('deleteItems removes all items + writes one history row each', () async {
      // Bulk delete should mirror single-delete: one Firestore delete + one
      // history "deleted" entry per item, all in a single atomic batch.
      final a = await seedItem(id: 'a', name: 'Apples', quantity: 4);
      final b = await seedItem(id: 'b', name: 'Bread', quantity: 1);
      final c = await seedItem(id: 'c', name: 'Cheese', quantity: 2);

      await service.deleteItems(householdId: 'hh1', items: [a, b, c]);

      final items = await fakeDb.collection('households/hh1/items').get();
      expect(items.docs, isEmpty);
      final hist = await fakeDb.collection('households/hh1/history').get();
      expect(hist.docs.length, 3);
      expect(hist.docs.every((d) => d['action'] == 'deleted'), isTrue);
      final names = hist.docs.map((d) => d['itemName']).toSet();
      expect(names, {'Apples', 'Bread', 'Cheese'});
    });

    test('deleteItems with empty list is a no-op', () async {
      await seedItem(id: 'a');
      await service.deleteItems(householdId: 'hh1', items: const []);
      final items = await fakeDb.collection('households/hh1/items').get();
      expect(items.docs.length, 1);
      final hist = await fakeDb.collection('households/hh1/history').get();
      expect(hist.docs, isEmpty);
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
