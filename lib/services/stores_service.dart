import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store.dart';

class StoresService {
  final FirebaseFirestore _db;
  StoresService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<Store>> storesStream(String householdId) {
    return _db.collection('households/$householdId/stores')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(Store.fromFirestore).toList());
  }

  Future<void> addStore(String householdId, String name, String uid) async {
    await _db.collection('households/$householdId/stores').add({
      'name': name, 'trolleySlug': null,
      'addedBy': uid, 'addedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameStore(String householdId, String storeId, String newName) async {
    await _db.doc('households/$householdId/stores/$storeId').update({'name': newName});
  }

  Future<void> removeStore(String householdId, String storeId) async {
    await _db.doc('households/$householdId/stores/$storeId').delete();
  }
}
