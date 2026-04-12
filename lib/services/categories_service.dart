import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoriesService {
  final FirebaseFirestore _db;
  CategoriesService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<GroceryCategory>> categoriesStream(String householdId) {
    return _db.collection('households/$householdId/categories')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(GroceryCategory.fromFirestore).toList());
  }

  Future<void> addCategory(String householdId, String name, Color color, String uid) async {
    await _db.collection('households/$householdId/categories').add({
      'name': name,
      'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'addedBy': uid,
      'addedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameCategory(String householdId, String categoryId, String newName) async {
    await _db.doc('households/$householdId/categories/$categoryId').update({'name': newName});
  }

  Future<void> updateCategory(String householdId, String categoryId, {String? name, Color? color}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (color != null) data['color'] = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    if (data.isNotEmpty) await _db.doc('households/$householdId/categories/$categoryId').update(data);
  }

  Future<void> deleteCategory(String householdId, String categoryId) async {
    final uncatSnap = await _db.collection('households/$householdId/categories')
        .where('name', isEqualTo: 'Uncategorised').limit(1).get();
    final uncatId = uncatSnap.docs.isNotEmpty ? uncatSnap.docs.first.id : 'uncategorised';

    final batch = _db.batch();
    final itemsSnap = await _db.collection('households/$householdId/items')
        .where('categoryId', isEqualTo: categoryId).get();
    for (final doc in itemsSnap.docs) { batch.update(doc.reference, {'categoryId': uncatId}); }
    final pantrySnap = await _db.collection('households/$householdId/pantry')
        .where('categoryId', isEqualTo: categoryId).get();
    for (final doc in pantrySnap.docs) { batch.update(doc.reference, {'categoryId': uncatId}); }
    batch.delete(_db.doc('households/$householdId/categories/$categoryId'));
    await batch.commit();
  }
}
