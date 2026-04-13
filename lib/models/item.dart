import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemSource { app, voiceInApp, googleHome }

extension ItemSourceExt on ItemSource {
  String get value => switch (this) {
    ItemSource.app => 'app',
    ItemSource.voiceInApp => 'voice_in_app',
    ItemSource.googleHome => 'google_home',
  };
  static ItemSource fromString(String s) => switch (s) {
    'voice_in_app' => ItemSource.voiceInApp,
    'google_home' => ItemSource.googleHome,
    _ => ItemSource.app,
  };
}

class AddedBy {
  final String? uid;
  final String displayName;
  final ItemSource source;
  const AddedBy({required this.uid, required this.displayName, required this.source});

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'source': source.value,
  };

  factory AddedBy.fromMap(Map<String, dynamic> m) => AddedBy(
    uid: m['uid'],
    displayName: m['displayName'] ?? 'Unknown',
    source: ItemSourceExt.fromString(m['source'] ?? 'app'),
  );
}

class ShoppingItem {
  final String id;
  final String name;
  final int quantity;
  final String? unit;
  final String? note;
  final String categoryId;
  final List<String> preferredStores;
  final String? pantryItemId;
  final String? recipeSource;
  final AddedBy addedBy;
  final DateTime addedAt;

  const ShoppingItem({
    required this.id, required this.name, required this.quantity,
    this.unit, this.note,
    required this.categoryId, required this.preferredStores,
    required this.pantryItemId, this.recipeSource, required this.addedBy,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name, 'quantity': quantity, 'unit': unit, 'note': note,
    'categoryId': categoryId,
    'preferredStores': preferredStores, 'pantryItemId': pantryItemId,
    'recipeSource': recipeSource,
    'addedBy': addedBy.toMap(),
    'addedAt': Timestamp.fromDate(addedAt),
  };

  factory ShoppingItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ShoppingItem(
      id: doc.id, name: d['name'] ?? '', quantity: d['quantity'] ?? 1,
      unit: d['unit'],
      note: d['note'],
      categoryId: d['categoryId'] ?? 'uncategorised',
      preferredStores: List<String>.from(d['preferredStores'] ?? []),
      pantryItemId: d['pantryItemId'],
      recipeSource: d['recipeSource'],
      addedBy: AddedBy.fromMap(d['addedBy'] ?? {}),
      addedAt: (d['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
