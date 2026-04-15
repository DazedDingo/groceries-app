import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads/writes household-shared user-supplied API keys at
/// `households/{id}/config/apiKeys`. Per-household scope means anyone in the
/// household uses the same keys (no re-entry per device or per partner) and
/// they survive uninstall/reinstall.
class HouseholdConfigService {
  final FirebaseFirestore _db;
  HouseholdConfigService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Stream of API keys. Missing fields surface as empty strings so callers
  /// can use `.isNotEmpty` checks without null-handling.
  Stream<Map<String, String>> apiKeysStream(String householdId) {
    return _db
        .doc('households/$householdId/config/apiKeys')
        .snapshots()
        .map((doc) {
      final data = doc.data() ?? {};
      return {
        'spoonacularKey': (data['spoonacularKey'] as String?) ?? '',
        'geminiKey': (data['geminiKey'] as String?) ?? '',
      };
    });
  }

  Future<void> setKey(
      String householdId, String fieldName, String value) async {
    await _db.doc('households/$householdId/config/apiKeys').set(
      {fieldName: value},
      SetOptions(merge: true),
    );
  }
}
