import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pantry_item.dart';

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
  }) async {
    final ref = await _db.collection('households/$householdId/pantry').add({
      'name': name, 'categoryId': categoryId, 'preferredStores': preferredStores,
      'optimalQuantity': optimalQuantity, 'currentQuantity': currentQuantity,
      'restockAfterDays': restockAfterDays,
      'shelfLifeDays': shelfLifeDays,
      'expiresAt': null,
      'lastNudgedAt': null, 'lastPurchasedAt': null,
    });
    return ref.id;
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
}
