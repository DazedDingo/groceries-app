import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pantry_item.dart'; // PantryItem only — PantryLocation kept for callers

class PantryService {
  final FirebaseFirestore _db;
  PantryService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<PantryItem>> pantryStream(String householdId) {
    return _db
        .collection('households/$householdId/pantry')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(PantryItem.fromFirestore).toList());
  }

  Future<String> addItem({
    required String householdId,
    required String name,
    required String categoryId,
    required List<String> preferredStores,
    required int optimalQuantity,
    required int currentQuantity,
    int? restockAfterDays,
    int? shelfLifeDays,
    String? unit,
    String? location,
  }) async {
    final ref = await _db.collection('households/$householdId/pantry').add({
      'name': name, 'categoryId': categoryId, 'preferredStores': preferredStores,
      'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
      'restockAfterDays': restockAfterDays,
      'shelfLifeDays': shelfLifeDays,
      'unit': unit,
      'expiresAt': null,
      'lastNudgedAt': null, 'lastPurchasedAt': null,
      'location': location,
    });
    return ref.id;
  }

  /// Bulk-create pantry items in a single atomic batch. Used by the voice
  /// bulk-add flow so a dictated list lands together rather than trickling in
  /// one Firestore round-trip per item. Callers provide both `currentQuantity`
  /// (what's on hand right now) and `optimalQuantity` (target stock level) —
  /// the voice review UI lets the user split them per item before committing.
  Future<void> addItems({
    required String householdId,
    required List<({
      String name,
      String categoryId,
      int currentQuantity,
      int optimalQuantity,
      String? unit,
    })> items,
  }) async {
    if (items.isEmpty) return;
    final batch = _db.batch();
    final col = _db.collection('households/$householdId/pantry');
    for (final item in items) {
      batch.set(col.doc(), {
        'name': item.name,
        'categoryId': item.categoryId,
        'preferredStores': <String>[],
        'optimalQuantity': item.optimalQuantity,
        'currentQuantity': item.currentQuantity,
        'restockAfterDays': null,
        'shelfLifeDays': null,
        'unit': item.unit,
        'expiresAt': null,
        'lastNudgedAt': null,
        'lastPurchasedAt': null,
        'location': null,
      });
    }
    await batch.commit();
  }

  Future<void> updateItem(String householdId, String itemId, Map<String, dynamic> updates) async {
    await _db.doc('households/$householdId/pantry/$itemId').update(updates);
  }

  Future<void> decrementQuantity({
    required String householdId,
    required String itemId,
    required int current,
  }) async {
    if (current <= 0) return;
    await _db.doc('households/$householdId/pantry/$itemId').update({
      'currentQuantity': FieldValue.increment(-1),
    });
  }

  Future<void> incrementQuantity({
    required String householdId,
    required String itemId,
    required int current,
  }) async {
    await _db.doc('households/$householdId/pantry/$itemId').update({
      'currentQuantity': FieldValue.increment(1),
    });
  }

  Future<void> clearExpired(String householdId, List<String> itemIds) async {
    final batch = _db.batch();
    for (final id in itemIds) {
      batch.update(_db.doc('households/$householdId/pantry/$id'), {
        'currentQuantity': 0,
        'expiresAt': null,
      });
    }
    await batch.commit();
  }

  Future<void> deleteItem(String householdId, String itemId) async {
    await _db.doc('households/$householdId/pantry/$itemId').delete();
  }

  /// Bulk-delete pantry items in a single batch. Pantry has no history log,
  /// so this is just N deletes committed atomically.
  Future<void> deleteItems({
    required String householdId,
    required List<String> itemIds,
  }) async {
    if (itemIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in itemIds) {
      batch.delete(_db.doc('households/$householdId/pantry/$id'));
    }
    await batch.commit();
  }
}
