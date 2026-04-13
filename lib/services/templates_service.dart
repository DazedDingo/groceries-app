import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shopping_template.dart';

class TemplatesService {
  final FirebaseFirestore _db;
  TemplatesService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<ShoppingTemplate>> templatesStream(String householdId) {
    return _db
        .collection('households/$householdId/templates')
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(ShoppingTemplate.fromFirestore).toList());
  }

  Future<String> addTemplate({
    required String householdId,
    required String name,
    required List<TemplateItem> items,
  }) async {
    final ref = await _db.collection('households/$householdId/templates').add({
      'name': name,
      'items': items.map((i) => i.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateTemplate({
    required String householdId,
    required String templateId,
    required String name,
    required List<TemplateItem> items,
  }) async {
    await _db.doc('households/$householdId/templates/$templateId').update({
      'name': name,
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  Future<void> deleteTemplate({
    required String householdId,
    required String templateId,
  }) async {
    await _db.doc('households/$householdId/templates/$templateId').delete();
  }
}
