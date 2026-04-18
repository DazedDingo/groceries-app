import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/items_service.dart';

PantryItem _pantryItem({
  String id = 'p1',
  String name = 'Cheddar',
  int current = 3,
  int optimal = 5,
  DateTime? runningLowAt,
}) =>
    PantryItem(
      id: id,
      name: name,
      categoryId: 'dairy',
      preferredStores: const [],
      optimalQuantity: optimal,
      currentQuantity: current,
      restockAfterDays: null,
      lastNudgedAt: null,
      lastPurchasedAt: null,
      runningLowAt: runningLowAt,
    );

const _addedBy = AddedBy(
  uid: 'u1',
  displayName: 'Alice',
  source: ItemSource.app,
);

void main() {
  group('ItemsService.promoteFromPantry', () {
    late FakeFirebaseFirestore db;
    late ItemsService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ItemsService(db: db);
    });

    Future<void> seedPantry(PantryItem p) async {
      await db.doc('households/hh1/pantry/${p.id}').set({
        'name': p.name,
        'categoryId': p.categoryId,
        'preferredStores': p.preferredStores,
        'optimalQuantity': p.optimalQuantity,
        'currentQuantity': p.currentQuantity,
        'restockAfterDays': null,
        'runningLowAt': p.runningLowAt != null
            ? Timestamp.fromDate(p.runningLowAt!)
            : null,
      });
    }

    test('writes shopping item + history + pantry update atomically', () async {
      final flaggedAt = DateTime(2026, 4, 15);
      final p = _pantryItem(runningLowAt: flaggedAt, current: 3, optimal: 5);
      await seedPantry(p);

      final shoppingId = await service.promoteFromPantry(
        householdId: 'hh1',
        pantryItem: p,
        listQuantity: 3,
        newPantryCurrent: 2,
        addedBy: _addedBy,
      );

      final shoppingSnap =
          await db.doc('households/hh1/items/$shoppingId').get();
      expect(shoppingSnap.exists, true);
      expect(shoppingSnap['name'], 'Cheddar');
      expect(shoppingSnap['quantity'], 3);
      expect(shoppingSnap['pantryItemId'], 'p1');
      expect(shoppingSnap['fromRunningLow'], true);

      final pantrySnap = await db.doc('households/hh1/pantry/p1').get();
      expect(pantrySnap['currentQuantity'], 2);
      expect(pantrySnap['runningLowAt'], isNull);

      final historyDocs =
          await db.collection('households/hh1/history').get();
      expect(historyDocs.docs, hasLength(1));
      expect(historyDocs.docs.first['itemName'], 'Cheddar');
    });

    test('fromRunningLow is true and survives re-parse via ShoppingItem.fromFirestore',
        () async {
      final p = _pantryItem(runningLowAt: DateTime(2026, 4, 15));
      await seedPantry(p);

      final shoppingId = await service.promoteFromPantry(
        householdId: 'hh1',
        pantryItem: p,
        listQuantity: 3,
        newPantryCurrent: 2,
        addedBy: _addedBy,
      );

      final doc = await db.doc('households/hh1/items/$shoppingId').get();
      final item = ShoppingItem.fromFirestore(doc);
      expect(item.fromRunningLow, true);
    });
  });

  group('ItemsService.undoPromoteFromPantry', () {
    late FakeFirebaseFirestore db;
    late ItemsService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ItemsService(db: db);
    });

    test('restores pantry state and removes the shopping item', () async {
      // Seed a post-promotion state directly.
      await db.doc('households/hh1/pantry/p1').set({
        'name': 'Cheddar',
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'optimalQuantity': 5,
        'currentQuantity': 2, // post-decrement
        'restockAfterDays': null,
        'runningLowAt': null, // cleared at promote
      });
      await db.doc('households/hh1/items/s1').set({
        'name': 'Cheddar',
        'quantity': 3,
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': 'p1',
        'fromRunningLow': true,
        'addedBy': _addedBy.toMap(),
        'addedAt': Timestamp.fromDate(DateTime(2026, 4, 18)),
      });

      final priorFlaggedAt = DateTime(2026, 4, 15);
      await service.undoPromoteFromPantry(
        householdId: 'hh1',
        shoppingItemId: 's1',
        pantryItemId: 'p1',
        restoredPantryCurrent: 3,
        restoredRunningLowAt: priorFlaggedAt,
      );

      final shoppingSnap = await db.doc('households/hh1/items/s1').get();
      expect(shoppingSnap.exists, false);

      final pantrySnap = await db.doc('households/hh1/pantry/p1').get();
      expect(pantrySnap['currentQuantity'], 3);
      expect(
        (pantrySnap['runningLowAt'] as Timestamp).toDate(),
        priorFlaggedAt,
      );
    });
  });

  group('promoteFromPantry → checkOff lands at optimal', () {
    test('round-trips a normal below-optimal item back to optimal', () async {
      final db = FakeFirebaseFirestore();
      final items = ItemsService(db: db);
      final p = _pantryItem(
        current: 3,
        optimal: 5,
        runningLowAt: DateTime(2026, 4, 15),
      );
      await db.doc('households/hh1/pantry/p1').set({
        'name': p.name,
        'categoryId': p.categoryId,
        'preferredStores': p.preferredStores,
        'optimalQuantity': p.optimalQuantity,
        'currentQuantity': p.currentQuantity,
        'restockAfterDays': null,
        'runningLowAt': Timestamp.fromDate(p.runningLowAt!),
      });

      final shoppingId = await items.promoteFromPantry(
        householdId: 'hh1',
        pantryItem: p,
        listQuantity: 3,
        newPantryCurrent: 2,
        addedBy: _addedBy,
      );

      // Cart it off. checkOff pulls quantity from the shopping item doc and
      // increments the pantry by that amount.
      final shoppingDoc =
          await db.doc('households/hh1/items/$shoppingId').get();
      final shoppingItem = ShoppingItem.fromFirestore(shoppingDoc);
      // Re-read pantry so PantryItem reflects the post-promote (decremented) state.
      final postPromoteDoc = await db.doc('households/hh1/pantry/p1').get();
      final postPromotePantry = PantryItem.fromFirestore(postPromoteDoc);

      await items.checkOff(
        householdId: 'hh1',
        item: shoppingItem,
        pantryItem: postPromotePantry,
      );

      final finalPantry = await db.doc('households/hh1/pantry/p1').get();
      expect(finalPantry['currentQuantity'], 5,
          reason: 'decrement on promote + increment on check-off should land at optimal');
    });

    test('single-container item (optimal=1, current=1) round-trips to 1', () async {
      final db = FakeFirebaseFirestore();
      final items = ItemsService(db: db);
      final p = _pantryItem(
        current: 1,
        optimal: 1,
        runningLowAt: DateTime(2026, 4, 15),
      );
      await db.doc('households/hh1/pantry/p1').set({
        'name': p.name,
        'categoryId': p.categoryId,
        'preferredStores': p.preferredStores,
        'optimalQuantity': p.optimalQuantity,
        'currentQuantity': p.currentQuantity,
        'restockAfterDays': null,
        'runningLowAt': Timestamp.fromDate(p.runningLowAt!),
      });

      final shoppingId = await items.promoteFromPantry(
        householdId: 'hh1',
        pantryItem: p,
        listQuantity: 1,
        newPantryCurrent: 0,
        addedBy: _addedBy,
      );
      final shoppingDoc =
          await db.doc('households/hh1/items/$shoppingId').get();
      final postPromoteDoc = await db.doc('households/hh1/pantry/p1').get();
      await items.checkOff(
        householdId: 'hh1',
        item: ShoppingItem.fromFirestore(shoppingDoc),
        pantryItem: PantryItem.fromFirestore(postPromoteDoc),
      );

      final finalPantry = await db.doc('households/hh1/pantry/p1').get();
      expect(finalPantry['currentQuantity'], 1);
    });
  });
}
