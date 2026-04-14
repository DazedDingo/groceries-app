import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/providers/items_provider.dart';
import 'package:groceries_app/providers/pantry_provider.dart';
import 'package:groceries_app/screens/shopping_list/cart_action.dart';
import 'package:groceries_app/services/items_service.dart';
import 'package:groceries_app/services/pantry_service.dart';

void main() {
  group('cartItemDetached', () {
    late FakeFirebaseFirestore fakeDb;
    late ProviderContainer container;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      container = ProviderContainer(
        overrides: [
          itemsServiceProvider.overrideWithValue(ItemsService(db: fakeDb)),
          pantryServiceProvider.overrideWithValue(PantryService(db: fakeDb)),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<ShoppingItem> seedShoppingItem({String? pantryItemId}) async {
      final ref = fakeDb.collection('households/hh1/items').doc('item1');
      await ref.set({
        'name': 'Milk',
        'quantity': 1,
        'unit': null,
        'note': null,
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': pantryItemId,
        'addedBy': {'uid': 'u1', 'displayName': 'Alice', 'source': 'app'},
        'addedAt': DateTime.now(),
      });
      final snap = await ref.get();
      return ShoppingItem.fromFirestore(snap);
    }

    test('removes item from list and creates pantry entry when not linked', () async {
      final item = await seedShoppingItem();

      final receipt = await cartItemDetached(container, 'hh1', item);

      final listSnap = await fakeDb.collection('households/hh1/items').get();
      expect(listSnap.docs, isEmpty,
          reason: 'shopping item should be removed from the list');

      final pantrySnap = await fakeDb.collection('households/hh1/pantry').get();
      expect(pantrySnap.docs.length, 1,
          reason: 'a pantry entry should be created for the unlinked item');
      expect(pantrySnap.docs.first['name'], 'Milk');
      expect(receipt.createdPantryItemId, pantrySnap.docs.first.id,
          reason: 'receipt should record the new pantry id for undo');
    });

    test('removes item from list without creating pantry entry when already linked',
        () async {
      // Seed an existing pantry doc so the link resolves cleanly.
      await fakeDb.collection('households/hh1/pantry').doc('p1').set({
        'name': 'Milk',
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'optimalQuantity': 2,
        'currentQuantity': 0,
        'lastBoughtAt': null,
        'shelfLifeDays': null,
      });
      final item = await seedShoppingItem(pantryItemId: 'p1');

      final receipt = await cartItemDetached(container, 'hh1', item);

      final listSnap = await fakeDb.collection('households/hh1/items').get();
      expect(listSnap.docs, isEmpty);

      final pantrySnap = await fakeDb.collection('households/hh1/pantry').get();
      expect(pantrySnap.docs.length, 1,
          reason: 'no duplicate pantry entry should be created');
      expect(receipt.createdPantryItemId, isNull,
          reason: 'no new pantry id when the item was already linked');
    });

    test('runs successfully even after the originating container is gone',
        () async {
      // Regression: user navigates away (screen state disposed) before the
      // snackbar's timer fires. The work captures a root container, so the
      // checkOff must still complete.
      final item = await seedShoppingItem();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cartItemDetached(container, 'hh1', item);

      final listSnap = await fakeDb.collection('households/hh1/items').get();
      expect(listSnap.docs, isEmpty);
      final pantrySnap = await fakeDb.collection('households/hh1/pantry').get();
      expect(pantrySnap.docs.length, 1);
    });
  });

  group('undoDetached', () {
    late FakeFirebaseFirestore fakeDb;
    late ProviderContainer container;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      container = ProviderContainer(
        overrides: [
          itemsServiceProvider.overrideWithValue(ItemsService(db: fakeDb)),
          pantryServiceProvider.overrideWithValue(PantryService(db: fakeDb)),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<ShoppingItem> seedShoppingItem({String? pantryItemId}) async {
      final ref = fakeDb.collection('households/hh1/items').doc('item1');
      await ref.set({
        'name': 'Milk',
        'quantity': 2,
        'unit': 'L',
        'note': 'organic',
        'categoryId': 'dairy',
        'preferredStores': <String>[],
        'pantryItemId': pantryItemId,
        'addedBy': {'uid': 'u1', 'displayName': 'Alice', 'source': 'app'},
        'addedAt': DateTime.now(),
      });
      final snap = await ref.get();
      return ShoppingItem.fromFirestore(snap);
    }

    test('after cart of unlinked item: removes new pantry entry and re-adds the item',
        () async {
      final item = await seedShoppingItem();
      final receipt = await cartItemDetached(container, 'hh1', item);
      // Sanity: pantry got the new entry.
      expect((await fakeDb.collection('households/hh1/pantry').get()).docs.length, 1);

      await undoDetached(container, 'hh1', receipt);

      final pantrySnap = await fakeDb.collection('households/hh1/pantry').get();
      expect(pantrySnap.docs, isEmpty,
          reason: 'undo must drop the pantry entry that cart created');
      final listSnap = await fakeDb.collection('households/hh1/items').get();
      expect(listSnap.docs.length, 1,
          reason: 'shopping item must be re-added on undo');
      expect(listSnap.docs.first['name'], 'Milk');
      expect(listSnap.docs.first['quantity'], 2);
      expect(listSnap.docs.first['unit'], 'L');
      expect(listSnap.docs.first['note'], 'organic');
    });

    test('after delete: re-adds the item without touching pantry', () async {
      // Existing unrelated pantry entry — undo of a delete must leave it alone.
      await fakeDb.collection('households/hh1/pantry').doc('p1').set({
        'name': 'Eggs', 'categoryId': 'dairy',
        'preferredStores': <String>[], 'optimalQuantity': 1,
        'currentQuantity': 1, 'shelfLifeDays': null,
      });
      final item = await seedShoppingItem();

      final receipt = await deleteItemDetached(container, 'hh1', item);
      expect(receipt.createdPantryItemId, isNull);

      await undoDetached(container, 'hh1', receipt);

      final listSnap = await fakeDb.collection('households/hh1/items').get();
      expect(listSnap.docs.length, 1);
      final pantrySnap = await fakeDb.collection('households/hh1/pantry').get();
      expect(pantrySnap.docs.length, 1,
          reason: 'unrelated pantry entry must not be touched');
      expect(pantrySnap.docs.first.id, 'p1');
    });
  });
}
