import 'package:cloud_firestore/cloud_firestore.dart';

class Store {
  final String id;
  final String name;
  final String? trolleySlug;
  final String addedBy;

  const Store({required this.id, required this.name, required this.trolleySlug, required this.addedBy});

  Map<String, dynamic> toMap() => {
    'name': name, 'trolleySlug': trolleySlug, 'addedBy': addedBy,
    'addedAt': FieldValue.serverTimestamp(),
  };

  factory Store.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Store(id: doc.id, name: d['name'], trolleySlug: d['trolleySlug'], addedBy: d['addedBy'] ?? '');
  }
}
