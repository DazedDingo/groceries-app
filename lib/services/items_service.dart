import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/item.dart';
import '../models/pantry_item.dart';
import '../models/history_entry.dart';

class ItemsService {
  final FirebaseFirestore _db;
  ItemsService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<ShoppingItem>> itemsStream(String householdId) {
    return _db
        .collection('households/$householdId/items')
        .orderBy('addedAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(ShoppingItem.fromFirestore).toList());
  }

  Stream<List<HistoryEntry>> historyStream(String householdId) {
    return _db
        .collection('households/$householdId/history')
        .orderBy('at', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(HistoryEntry.fromFirestore).toList());
  }

  Future<void> addItem({
    required String householdId,
    required String name,
    required String categoryId,
    required List<String> preferredStores,
    required String? pantryItemId,
    required AddedBy addedBy,
    int quantity = 1,
    String? unit,
    String? note,
    String? recipeSource,
    bool isRecurring = false,
  }) async {
    final batch = _db.batch();
    final itemRef = _db.collection('households/$householdId/items').doc();
    batch.set(itemRef, {
      'name': name, 'quantity': quantity, 'unit': unit, 'note': note,
      'categoryId': categoryId,
      'preferredStores': preferredStores, 'pantryItemId': pantryItemId,
      'recipeSource': recipeSource,
      'isRecurring': isRecurring,
      'addedBy': addedBy.toMap(), 'addedAt': FieldValue.serverTimestamp(),
    });
    final histRef = _db.collection('households/$householdId/history').doc();
    batch.set(histRef, HistoryEntry.toMap(
      itemName: name, categoryId: categoryId,
      action: HistoryAction.added, quantity: quantity,
      byName: addedBy.displayName,
    ));
    await batch.commit();
  }

  /// Bulk add: writes all items + their history entries in a single batch.
  /// More efficient than looping `addItem` and avoids partial-write states.
  Future<void> addItems({
    required String householdId,
    required List<({String name, String categoryId, int quantity, String? unit})> items,
    required AddedBy addedBy,
  }) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    for (final item in items) {
      final itemRef = _db.collection('households/$householdId/items').doc();
      batch.set(itemRef, {
        'name': item.name,
        'quantity': item.quantity,
        'unit': item.unit,
        'note': null,
        'categoryId': item.categoryId,
        'preferredStores': <String>[],
        'pantryItemId': null,
        'recipeSource': null,
        'isRecurring': false,
        'addedBy': addedBy.toMap(),
        'addedAt': FieldValue.serverTimestamp(),
      });
      final histRef = _db.collection('households/$householdId/history').doc();
      batch.set(histRef, HistoryEntry.toMap(
        itemName: item.name, categoryId: item.categoryId,
        action: HistoryAction.added, quantity: item.quantity,
        byName: addedBy.displayName,
      ));
    }
    await batch.commit();
  }

  Future<void> updateItem({
    required String householdId,
    required String itemId,
    required String name,
    required int quantity,
    required String? unit,
    String? note,
    required String categoryId,
  }) async {
    await _db.doc('households/$householdId/items/$itemId').update({
      'name': name, 'quantity': quantity, 'unit': unit, 'note': note,
      'categoryId': categoryId,
    });
  }

  Future<void> deleteItem({
    required String householdId,
    required ShoppingItem item,
  }) async {
    final batch = _db.batch();
    batch.delete(_db.doc('households/$householdId/items/${item.id}'));
    final histRef = _db.collection('households/$householdId/history').doc();
    batch.set(histRef, HistoryEntry.toMap(
      itemName: item.name, categoryId: item.categoryId,
      action: HistoryAction.deleted, quantity: item.quantity,
      byName: item.addedBy.displayName,
    ));
    await batch.commit();
  }

  Future<void> checkOff({
    required String householdId,
    required ShoppingItem item,
    PantryItem? pantryItem,
  }) async {
    final batch = _db.batch();
    batch.delete(_db.doc('households/$householdId/items/${item.id}'));
    if (pantryItem != null) {
      // Use the explicit link if available, otherwise fall back to the matched item's id.
      final pantryId = item.pantryItemId ?? pantryItem.id;
      // Only increment quantity when units are compatible (both null, or both equal).
      // A mismatch (e.g. list "2 pieces" vs pantry "200g") would corrupt the number,
      // so we skip the increment but still update lastPurchasedAt.
      final unitsCompatible = item.unit == pantryItem.unit;
      final updates = <String, dynamic>{
        if (unitsCompatible) 'currentQuantity': FieldValue.increment(item.quantity),
        'lastPurchasedAt': FieldValue.serverTimestamp(),
      };
      if (pantryItem.shelfLifeDays != null) {
        updates['expiresAt'] = Timestamp.fromDate(
          DateTime.now().add(Duration(days: pantryItem.shelfLifeDays!)),
        );
      }
      batch.update(
        _db.doc('households/$householdId/pantry/$pantryId'),
        updates,
      );
    }
    final histRef = _db.collection('households/$householdId/history').doc();
    batch.set(histRef, HistoryEntry.toMap(
      itemName: item.name, categoryId: item.categoryId,
      action: HistoryAction.bought, quantity: item.quantity,
      byName: item.addedBy.displayName,
    ));
    await batch.commit();
  }

  /// Batch-remove multiple items as "bought" (confirm at till flow).
  Future<void> confirmBought({
    required String householdId,
    required List<ShoppingItem> items,
    required Map<String, PantryItem> pantryItems,
  }) async {
    final batch = _db.batch();
    for (final item in items) {
      batch.delete(_db.doc('households/$householdId/items/${item.id}'));
      if (item.pantryItemId != null && pantryItems.containsKey(item.pantryItemId)) {
        final pi = pantryItems[item.pantryItemId]!;
        final unitsCompatible = item.unit == pi.unit;
        final updates = <String, dynamic>{
          if (unitsCompatible) 'currentQuantity': FieldValue.increment(item.quantity),
          'lastPurchasedAt': FieldValue.serverTimestamp(),
        };
        if (pi.shelfLifeDays != null) {
          updates['expiresAt'] = Timestamp.fromDate(
            DateTime.now().add(Duration(days: pi.shelfLifeDays!)),
          );
        }
        batch.update(
          _db.doc('households/$householdId/pantry/${item.pantryItemId}'),
          updates,
        );
      }
      final histRef = _db.collection('households/$householdId/history').doc();
      batch.set(histRef, HistoryEntry.toMap(
        itemName: item.name, categoryId: item.categoryId,
        action: HistoryAction.bought, quantity: item.quantity,
        byName: item.addedBy.displayName,
      ));
    }
    await batch.commit();
  }
}
