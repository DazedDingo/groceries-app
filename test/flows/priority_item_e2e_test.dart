/// E2E: high-priority pantry item flow
///
/// Verifies the full path:
///   pantry item marked isHighPriority=true + below optimal
///   → shopping list receives a matching item from restock/manual add
///   → isHighPriorityItem classification returns true for that item
///   → classification returns false for normal items
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/models/pantry_item.dart';
import 'package:groceries_app/services/items_service.dart';
import 'package:groceries_app/services/pantry_service.dart';

// Mirrors the isHighPriorityItem logic used in shopping_list_screen.dart
// so we can test it in isolation without spinning up the widget tree.
bool isHighPriorityItem(ShoppingItem item, List<PantryItem> pantryItems) {
  if (item.pantryItemId == null) return false;
  final pantry = pantryItems.where((p) => p.id == item.pantryItemId).firstOrNull;
  return pantry != null && pantry.isHighPriority && pantry.isBelowOptimal;
}

void main() {
  group('priority item e2e', () {
    late FakeFirebaseFirestore fakeDb;
    late PantryService pantryService;
    late ItemsService itemsService;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      pantryService = PantryService(db: fakeDb);
      itemsService = ItemsService(db: fakeDb);
    });

    test('item linked to high-priority pantry item below optimal is classified as priority', () async {
      // Seed a high-priority pantry item that is below optimal
      await fakeDb.doc('households/hh1/pantry/p-milk').set({
        'name': 'milk', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 4, 'currentQuantity': 1,
        'restockAfterDays': 7, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': true,
      });

      // Add it to the shopping list (simulating restock nudge or manual add)
      await itemsService.addItem(
        householdId: 'hh1',
        name: 'milk',
        categoryId: 'dairy',
        preferredStores: const [],
        pantryItemId: 'p-milk',
        quantity: 3,
        addedBy: const AddedBy(uid: 'system', displayName: 'Restock nudge', source: ItemSource.app),
      );

      final pantryItems = await pantryService.pantryStream('hh1').first;
      final shoppingItems = await itemsService.itemsStream('hh1').first;

      expect(pantryItems, hasLength(1));
      expect(shoppingItems, hasLength(1));
      expect(isHighPriorityItem(shoppingItems.first, pantryItems), isTrue);
    });

    test('item without pantryItemId is not classified as priority', () async {
      await itemsService.addItem(
        householdId: 'hh1',
        name: 'bread',
        categoryId: 'bakery',
        preferredStores: const [],
        pantryItemId: null,
        quantity: 1,
        addedBy: const AddedBy(uid: 'u1', displayName: 'User', source: ItemSource.app),
      );

      final pantryItems = await pantryService.pantryStream('hh1').first;
      final shoppingItems = await itemsService.itemsStream('hh1').first;

      expect(isHighPriorityItem(shoppingItems.first, pantryItems), isFalse);
    });

    test('item linked to high-priority pantry item AT optimal is not classified as priority', () async {
      await fakeDb.doc('households/hh1/pantry/p-butter').set({
        'name': 'butter', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 2, 'currentQuantity': 2, // at optimal
        'restockAfterDays': null, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': true,
      });

      await itemsService.addItem(
        householdId: 'hh1',
        name: 'butter',
        categoryId: 'dairy',
        preferredStores: const [],
        pantryItemId: 'p-butter',
        quantity: 1,
        addedBy: const AddedBy(uid: 'u1', displayName: 'User', source: ItemSource.app),
      );

      final pantryItems = await pantryService.pantryStream('hh1').first;
      final shoppingItems = await itemsService.itemsStream('hh1').first;

      expect(isHighPriorityItem(shoppingItems.first, pantryItems), isFalse);
    });

    test('item linked to NON-priority pantry item below optimal is not classified as priority', () async {
      await fakeDb.doc('households/hh1/pantry/p-pasta').set({
        'name': 'pasta', 'categoryId': 'dry-goods', 'preferredStores': [],
        'optimalQuantity': 3, 'currentQuantity': 0,
        'restockAfterDays': 14, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': false,
      });

      await itemsService.addItem(
        householdId: 'hh1',
        name: 'pasta',
        categoryId: 'dry-goods',
        preferredStores: const [],
        pantryItemId: 'p-pasta',
        quantity: 3,
        addedBy: const AddedBy(uid: 'u1', displayName: 'User', source: ItemSource.app),
      );

      final pantryItems = await pantryService.pantryStream('hh1').first;
      final shoppingItems = await itemsService.itemsStream('hh1').first;

      expect(isHighPriorityItem(shoppingItems.first, pantryItems), isFalse);
    });

    test('marking high-priority item as no longer high priority un-classifies it', () async {
      await fakeDb.doc('households/hh1/pantry/p-milk').set({
        'name': 'milk', 'categoryId': 'dairy', 'preferredStores': [],
        'optimalQuantity': 4, 'currentQuantity': 0,
        'restockAfterDays': 7, 'lastNudgedAt': null, 'lastPurchasedAt': null,
        'isHighPriority': true,
      });

      await itemsService.addItem(
        householdId: 'hh1',
        name: 'milk',
        categoryId: 'dairy',
        preferredStores: const [],
        pantryItemId: 'p-milk',
        quantity: 4,
        addedBy: const AddedBy(uid: 'u1', displayName: 'User', source: ItemSource.app),
      );

      // Toggle off priority
      await pantryService.updateItem('hh1', 'p-milk', {'isHighPriority': false});

      final pantryItems = await pantryService.pantryStream('hh1').first;
      final shoppingItems = await itemsService.itemsStream('hh1').first;

      expect(isHighPriorityItem(shoppingItems.first, pantryItems), isFalse);
    });
  });
}
