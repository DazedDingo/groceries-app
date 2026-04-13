import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryOverrideService {
  final FirebaseFirestore _db;
  CategoryOverrideService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference _ref(String householdId) =>
      _db.collection('households/$householdId/categoryOverrides');

  /// Save a user's category correction so future guesses use it.
  Future<void> saveOverride({
    required String householdId,
    required String itemName,
    required String categoryId,
  }) async {
    final key = itemName.trim().toLowerCase();
    if (key.isEmpty) return;
    await _ref(householdId).doc(key).set({
      'categoryId': categoryId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream all overrides as a map of lowercase item name → categoryId.
  Stream<Map<String, String>> overridesStream(String householdId) {
    return _ref(householdId).snapshots().map((snap) {
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final catId = doc['categoryId'] as String?;
        if (catId != null) map[doc.id] = catId;
      }
      return map;
    });
  }
}
