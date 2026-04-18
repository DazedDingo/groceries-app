import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:groceries_app/services/pantry_service.dart';

void main() {
  group('PantryService', () {
    late PantryService service;
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = PantryService(db: fakeDb);
    });

    Future<void> seedItem({
      String id = 'p1',
      int currentQuantity = 3,
      int optimalQuantity = 6,
      bool isHighPriority = false,
    }) => fakeDb.doc('households/hh1/pantry/$id').set({
      'name': 'Milk', 'categoryId': 'dairy', 'preferredStores': [],
      'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
      'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
      'isHighPriority': isHighPriority,
    });

    test('decrementQuantity reduces currentQuantity by 1', () async {
      await seedItem(currentQuantity: 3);
      await service.decrementQuantity(householdId: 'hh1', itemId: 'p1', current: 3);
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['currentQuantity'], 2);
    });

    test('decrementQuantity does nothing when current is 0', () async {
      await seedItem(currentQuantity: 0);
      await service.decrementQuantity(householdId: 'hh1', itemId: 'p1', current: 0);
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['currentQuantity'], 0);
    });

    test('incrementQuantity increases currentQuantity by 1', () async {
      await seedItem(currentQuantity: 3);
      await service.incrementQuantity(householdId: 'hh1', itemId: 'p1', current: 3);
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['currentQuantity'], 4);
    });

    test('updateItem persists isHighPriority true', () async {
      await seedItem();
      await service.updateItem('hh1', 'p1', {'isHighPriority': true});
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['isHighPriority'], isTrue);
    });

    test('updateItem persists isHighPriority false', () async {
      await seedItem(isHighPriority: true);
      await service.updateItem('hh1', 'p1', {'isHighPriority': false});
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['isHighPriority'], isFalse);
    });

    test('updateItem persists optimalQuantity', () async {
      await seedItem();
      await service.updateItem('hh1', 'p1', {'optimalQuantity': 12});
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['optimalQuantity'], 12);
    });

    test('pantryStream emits items with isHighPriority from Firestore', () async {
      await seedItem(isHighPriority: true);
      final items = await service.pantryStream('hh1').first;
      expect(items.first.isHighPriority, isTrue);
    });

    test('addItems writes all rows in a single batch with provided current/optimal', () async {
      await service.addItems(householdId: 'hh1', items: [
        (name: 'Pasta', categoryId: 'pantry', currentQuantity: 3, optimalQuantity: 6, unit: null),
        (name: 'Tomato tins', categoryId: 'pantry', currentQuantity: 0, optimalQuantity: 4, unit: null),
        (name: 'Olive oil', categoryId: 'pantry', currentQuantity: 1, optimalQuantity: 1, unit: 'L'),
      ]);
      final snap = await fakeDb.collection('households/hh1/pantry').get();
      expect(snap.docs.length, 3);
      final byName = {for (final d in snap.docs) d['name']: d.data()};
      expect(byName['Pasta']!['currentQuantity'], 3);
      expect(byName['Pasta']!['optimalQuantity'], 6);
      expect(byName['Tomato tins']!['currentQuantity'], 0);
      expect(byName['Tomato tins']!['optimalQuantity'], 4);
      expect(byName['Olive oil']!['unit'], 'L');
      // Every row gets the defaulted fields so the document shape matches
      // what addItem() produces — downstream readers don't need special cases.
      for (final d in snap.docs) {
        expect(d['preferredStores'], <String>[]);
        expect(d['location'], isNull);
        expect(d['expiresAt'], isNull);
      }
    });

    test('addItems is a no-op on an empty payload (no writes, no throw)', () async {
      await service.addItems(householdId: 'hh1', items: []);
      final snap = await fakeDb.collection('households/hh1/pantry').get();
      expect(snap.docs, isEmpty);
    });

    test('deleteItems removes only the listed ids in a single batch', () async {
      await seedItem(id: 'p1');
      await fakeDb.doc('households/hh1/pantry/p2').set({
        'name': 'Bread', 'categoryId': 'bakery', 'preferredStores': [],
        'optimalQuantity': 1, 'currentQuantity': 1,
        'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': false,
      });
      await fakeDb.doc('households/hh1/pantry/p3').set({
        'name': 'Cheese', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 1, 'currentQuantity': 1,
        'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': false,
      });

      await service.deleteItems(householdId: 'hh1', itemIds: ['p1', 'p3']);

      final snap = await fakeDb.collection('households/hh1/pantry').get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.id, 'p2');
    });

    test('deleteItems with empty list is a no-op', () async {
      await seedItem();
      await service.deleteItems(householdId: 'hh1', itemIds: const []);
      final snap = await fakeDb.collection('households/hh1/pantry').get();
      expect(snap.docs.length, 1);
    });

    test('markRunningLow sets runningLowAt to the given timestamp', () async {
      await seedItem();
      final now = DateTime(2026, 4, 18, 10);
      await service.markRunningLow(
        householdId: 'hh1', itemId: 'p1', at: now,
      );
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect((doc['runningLowAt'] as dynamic).toDate(), now);
    });

    test('clearRunningLow resets runningLowAt to null', () async {
      await seedItem();
      await service.markRunningLow(
        householdId: 'hh1', itemId: 'p1', at: DateTime(2026, 4, 18),
      );
      await service.clearRunningLow(householdId: 'hh1', itemId: 'p1');
      final doc = await fakeDb.doc('households/hh1/pantry/p1').get();
      expect(doc['runningLowAt'], isNull);
    });

    test('pantryStream defaults isHighPriority to false for legacy items', () async {
      // Legacy items written before the field existed have no isHighPriority key
      await fakeDb.doc('households/hh1/pantry/legacy').set({
        'name': 'Eggs', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 6, 'currentQuantity': 2,
        'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        // no isHighPriority key — simulates data written before this feature
      });
      final items = await service.pantryStream('hh1').first;
      final legacy = items.firstWhere((i) => i.id == 'legacy');
      expect(legacy.isHighPriority, isFalse);
    });
  });
}
