import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages user-defined custom pantry locations stored per household.
/// Built-in locations (fridge, freezer, etc.) are handled by [PantryLocation]
/// in the model; this service only deals with the custom ones.
class LocationService {
  final FirebaseFirestore _db;
  LocationService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<String>> customLocationsStream(String householdId) {
    return _db
        .doc('households/$householdId/config/locations')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data();
      return List<String>.from(data?['labels'] ?? []);
    });
  }

  Future<void> addLocation(String householdId, String label) async {
    await _db.doc('households/$householdId/config/locations').set(
      {'labels': FieldValue.arrayUnion([label])},
      SetOptions(merge: true),
    );
  }

  Future<void> removeLocation(String householdId, String label) async {
    await _db.doc('households/$householdId/config/locations').update(
      {'labels': FieldValue.arrayRemove([label])},
    );
  }
}
