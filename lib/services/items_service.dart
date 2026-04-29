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

  /// Returns the new shopping-item doc id so callers can drive an
  /// Undo flow (the auto-add-on-below-optimal path in pantry_screen
  /// uses this for the snackbar's deleteItem). Existing callers that
  /// don't care about the id can ignore the return.
  Future<String> addItem({
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
    return itemRef.id;
  }

  /// Atomic running-low promotion: inserts the shopping item + history entry
  /// AND clears the pantry `runningLowAt` flag + decrements `currentQuantity`
  /// in a single batched write. Prevents the drift where the add succeeds but
  /// the pantry update fails (item on list, flag still set, count undecremented).
  Future<String> promoteFromPantry({
    required String householdId,
    required PantryItem pantryItem,
    required int listQuantity,
    required int newPantryCurrent,
    required AddedBy addedBy,
  }) async {
    final batch = _db.batch();
    final itemRef = _db.collection('households/$householdId/items').doc();
    batch.set(itemRef, {
      'name': pantryItem.name,
      'quantity': listQuantity,
      'unit': pantryItem.unit,
      'note': null,
      'categoryId': pantryItem.categoryId,
      'preferredStores': pantryItem.preferredStores,
      'pantryItemId': pantryItem.id,
      'recipeSource': null,
      'isRecurring': false,
      'fromRunningLow': true,
      'addedBy': addedBy.toMap(),
      'addedAt': FieldValue.serverTimestamp(),
    });
    final histRef = _db.collection('households/$householdId/history').doc();
    batch.set(histRef, HistoryEntry.toMap(
      itemName: pantryItem.name, categoryId: pantryItem.categoryId,
      action: HistoryAction.added, quantity: listQuantity,
      byName: addedBy.displayName,
    ));
    batch.update(_db.doc('households/$householdId/pantry/${pantryItem.id}'), {
      'currentQuantity': newPantryCurrent,
      'runningLowAt': null,
    });
    await batch.commit();
    return itemRef.id;
  }

  /// Reverse a running-low promotion: delete the auto-added shopping item,
  /// restore the pantry's `currentQuantity`, and re-set the `runningLowAt`
  /// flag. Used by the snackbar Undo action.
  Future<void> undoPromoteFromPantry({
    required String householdId,
    required String shoppingItemId,
    required String pantryItemId,
    required int restoredPantryCurrent,
    required DateTime restoredRunningLowAt,
  }) async {
    final batch = _db.batch();
    batch.delete(_db.doc('households/$householdId/items/$shoppingItemId'));
    batch.update(_db.doc('households/$householdId/pantry/$pantryItemId'), {
      'currentQuantity': restoredPantryCurrent,
      'runningLowAt': Timestamp.fromDate(restoredRunningLowAt),
    });
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

  /// Bulk-delete shopping items. Each item gets its own history entry so the
  /// audit log reflects one "deleted" line per item (matching single-delete
  /// behaviour) rather than a single bulk marker that readers would have to
  /// special-case.
  Future<void> deleteItems({
    required String householdId,
    required List<ShoppingItem> items,
  }) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    for (final item in items) {
      batch.delete(_db.doc('households/$householdId/items/${item.id}'));
      final histRef = _db.collection('households/$householdId/history').doc();
      batch.set(histRef, HistoryEntry.toMap(
        itemName: item.name, categoryId: item.categoryId,
        action: HistoryAction.deleted, quantity: item.quantity,
        byName: item.addedBy.displayName,
      ));
    }
    await batch.commit();
  }

  Future<void> checkOff({
    required String householdId,
    required ShoppingItem item,
    PantryItem? pantryItem,
    /// Days to use as a shelf-life fallback when `pantryItem.shelfLifeDays` is
    /// null. When non-null and used, it's also persisted to the pantry doc so
    /// future check-offs stop needing to guess.
    int? shelfLifeDaysFallback,
  }) async {
    final batch = _db.batch();
    batch.delete(_db.doc('households/$householdId/items/${item.id}'));
    if (pantryItem != null) {
      final pantryId = item.pantryItemId ?? pantryItem.id;
      final unitsCompatible = item.unit == pantryItem.unit;
      final updates = <String, dynamic>{
        if (unitsCompatible) 'currentQuantity': FieldValue.increment(item.quantity),
        'lastPurchasedAt': FieldValue.serverTimestamp(),
      };
      final effectiveShelfLife =
          pantryItem.shelfLifeDays ?? shelfLifeDaysFallback;
      if (effectiveShelfLife != null) {
        // Always restart the countdown on buy so the banner reflects the
        // freshly-purchased item, not the leftover from the previous batch.
        updates['expiresAt'] = Timestamp.fromDate(
          DateTime.now().add(Duration(days: effectiveShelfLife)),
        );
        if (pantryItem.shelfLifeDays == null) {
          updates['shelfLifeDays'] = effectiveShelfLife;
        }
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
    /// Keyed by pantry-item id: the shelf-life fallback to apply when that
    /// pantry entry has no `shelfLifeDays` set.
    Map<String, int>? shelfLifeDaysFallbacks,
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
        final effectiveShelfLife = pi.shelfLifeDays ??
            shelfLifeDaysFallbacks?[item.pantryItemId];
        if (effectiveShelfLife != null) {
          updates['expiresAt'] = Timestamp.fromDate(
            DateTime.now().add(Duration(days: effectiveShelfLife)),
          );
          if (pi.shelfLifeDays == null) {
            updates['shelfLifeDays'] = effectiveShelfLife;
          }
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
